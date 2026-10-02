import XCTest
@testable import Mousse

/// Pure dispatch layer of the command socket: protocol versioning, unknown commands, the
/// get/set key whitelist, value coercion (bools must be REAL booleans — `1` is rejected), and
/// the quit side-action. The delegate here is canned state; socket I/O is covered in
/// CommandSocketTests.
final class CommandRouterTests: XCTestCase {

    private final class MockDelegate: CommandRouter.Delegate {
        var statusPayload: [String: Any] = ["engine": "on"]
        var diagnosticsPayload: [String: Any] = ["health": "healthy"]
        var getTable: [String: CommandRouter.ConfigValue] = [
            "enabled": .bool(true),
            "scrollSpeed": .number(0.5),
            "scrollMode": .string("smooth"),
        ]
        private(set) var sets: [(key: String, value: CommandRouter.ConfigValue)] = []
        var setAccepted = true

        func status() -> [String: Any] { statusPayload }
        func diagnostics() -> [String: Any] { diagnosticsPayload }
        func get(key: String) -> CommandRouter.ConfigValue? { getTable[key] }
        func set(key: String, value: CommandRouter.ConfigValue) -> Bool {
            sets.append((key, value))
            return setAccepted
        }
    }

    private var delegate = MockDelegate()

    override func setUp() {
        super.setUp()
        delegate = MockDelegate()
    }

    private func route(_ request: [String: Any]) -> (response: [String: Any], after: CommandRouter.PostReplyAction?) {
        CommandRouter.route(request, delegate: delegate)
    }

    private func request(cmd: String, key: String? = nil, value: Any? = nil) -> [String: Any] {
        var r: [String: Any] = ["v": CommandRouter.protocolVersion, "cmd": cmd]
        if let key { r["key"] = key }
        if let value { r["value"] = value }
        return r
    }

    // MARK: Envelope

    func testWrongOrMissingProtocolVersionIsRejected() {
        for v in [0, 2, "1"] {
            let (response, after) = route(["v": v, "cmd": "status"])
            XCTAssertNil(after)
            XCTAssertEqual(response["ok"] as? Bool, false)
            XCTAssertNotNil(response["error"])
        }
        let (missing, _) = route(["cmd": "status"])
        XCTAssertEqual(missing["ok"] as? Bool, false)
    }

    /// JSON `true` bridges to NSNumber(1); the version check must reject it rather than
    /// silently treating the protocol version as the integer 1.
    func testBooleanProtocolVersionIsRejected() {
        for v in [true, false] as [Any] {
            let (response, after) = route(["v": v, "cmd": "status"])
            XCTAssertNil(after)
            XCTAssertEqual(response["ok"] as? Bool, false)
            XCTAssertNotNil(response["error"])
        }
    }

    func testUnknownCommandAndMissingCmdAreRejected() {
        let (bogus, _) = route(request(cmd: "launchMissiles"))
        XCTAssertEqual(bogus["ok"] as? Bool, false)
        XCTAssertTrue((bogus["error"] as? String)?.contains("unknown command") ?? false)

        let (none, _) = route(["v": CommandRouter.protocolVersion])
        XCTAssertEqual(none["ok"] as? Bool, false)
    }

    func testStatusAndDiagnosticsWrapDelegatePayload() {
        for (cmd, payload) in [("status", delegate.statusPayload), ("diagnostics", delegate.diagnosticsPayload)] {
            let (response, after) = route(request(cmd: cmd))
            XCTAssertNil(after)
            XCTAssertEqual(response["ok"] as? Bool, true)
            XCTAssertEqual(response["v"] as? Int, CommandRouter.protocolVersion)
            for (k, v) in payload {
                XCTAssertEqual(response[k] as? String, v as? String, "payload key \(k) must pass through")
            }
        }
    }

    // MARK: get

    func testGetReturnsDelegateValueAndUnknownKeyErrors() {
        let (ok, _) = route(request(cmd: "get", key: "scrollSpeed"))
        XCTAssertEqual(ok["ok"] as? Bool, true)
        XCTAssertEqual(ok["key"] as? String, "scrollSpeed")
        XCTAssertEqual(ok["value"] as? Double, 0.5)

        let (unknown, _) = route(request(cmd: "get", key: "nope"))
        XCTAssertEqual(unknown["ok"] as? Bool, false)
        XCTAssertTrue((unknown["error"] as? String)?.contains("unknown key") ?? false)
    }

    func testGetAndSetAcceptExactlyTheWhitelistedKeys() {
        let supported = Set(CommandRouter.supportedKeys)
        XCTAssertEqual(supported, ["enabled", "reverseScroll", "reverseScrollHorizontal", "scrollAcceleration", "smoothHighRes",
                                   "edgeScroll", "scrollSpeed", "zoomSpeed", "edgeScrollSpeed",
                                   "scrollMode", "scrollSmoothness"])
        // The help text must mention every supported key — it is the CLI's discoverability.
        for key in supported {
            XCTAssertTrue(CommandRouter.keysHelp.contains(key), "help text missing key \(key)")
        }
    }

    // MARK: set — bool keys accept only real booleans

    func testSetBoolKeysAcceptTrueAndFalseOnly() {
        for key in ["enabled", "reverseScroll", "reverseScrollHorizontal", "scrollAcceleration", "smoothHighRes", "edgeScroll"] {
            for v in [true, false] {
                let (response, _) = route(request(cmd: "set", key: key, value: v))
                XCTAssertEqual(response["ok"] as? Bool, true, "\(key) = \(v)")
                XCTAssertEqual(delegate.sets.last?.key, key)
            }
            // JSON 1 / 0 / "true" (a string) must NOT silently become a boolean.
            for bad in [1, 0, 5.0, "true", "false"] {
                let (response, _) = route(request(cmd: "set", key: key, value: bad))
                XCTAssertEqual(response["ok"] as? Bool, false, "\(key) must reject \(bad)")
            }
        }
    }

    // MARK: set — number keys are range-checked

    func testSetNumberKeysAcceptIntsAndDoublesInRange() {
        let (ok, _) = route(request(cmd: "set", key: "scrollSpeed", value: 1))
        XCTAssertEqual(ok["ok"] as? Bool, true, "integer must be accepted for a double key")
        XCTAssertEqual(delegate.sets.last?.value, .number(1.0))

        let (okDouble, _) = route(request(cmd: "set", key: "zoomSpeed", value: 2.5))
        XCTAssertEqual(okDouble["ok"] as? Bool, true)

        // Out of range → rejected with the allowed range in the message.
        for (key, bad) in [("scrollSpeed", 3.01), ("scrollSpeed", 0.04), ("zoomSpeed", 0.1), ("edgeScrollSpeed", 10_000)] {
            let (response, _) = route(request(cmd: "set", key: key, value: bad))
            XCTAssertEqual(response["ok"] as? Bool, false, "\(key) = \(bad) must be rejected")
            XCTAssertTrue((response["error"] as? String)?.contains(key) ?? false)
        }
        // Booleans are not numbers, even though NSNumber bridges them.
        let (boolAsNumber, _) = route(request(cmd: "set", key: "scrollSpeed", value: true))
        XCTAssertEqual(boolAsNumber["ok"] as? Bool, false)
    }

    // MARK: set — enum keys accept only listed raw values

    func testSetEnumKeysValidateRawValues() {
        for (key, good) in [("scrollMode", "native"), ("scrollMode", "standard"), ("scrollMode", "smooth"), ("scrollMode", "smoothStep"), ("scrollSmoothness", "floaty")] {
            let (ok, _) = route(request(cmd: "set", key: key, value: good))
            XCTAssertEqual(ok["ok"] as? Bool, true)
            XCTAssertEqual(delegate.sets.last?.value, .string(good))
        }
        for (key, bad) in [("scrollMode", "smoothest"), ("scrollSmoothness", "somewhat floaty")] {
            let (response, _) = route(request(cmd: "set", key: key, value: bad))
            XCTAssertEqual(response["ok"] as? Bool, false)
        }
        for (key, bad) in [("scrollMode", 2), ("scrollSmoothness", 1.5)] {
            let (response, _) = route(request(cmd: "set", key: key, value: bad))
            XCTAssertEqual(response["ok"] as? Bool, false, "numbers must not pass for enum key \(key)")
        }
    }

    func testSetUnknownKeyIsRejectedWithoutTouchingDelegate() {
        let (response, _) = route(request(cmd: "set", key: "mappings", value: "x"))
        XCTAssertEqual(response["ok"] as? Bool, false)
        XCTAssertTrue(delegate.sets.isEmpty)
    }

    func testSetDelegateRejectionSurfacesAsError() {
        delegate.setAccepted = false
        let (response, _) = route(request(cmd: "set", key: "enabled", value: true))
        XCTAssertEqual(response["ok"] as? Bool, false)
    }

    // MARK: quit

    func testQuitAsksForTerminateAfterReply() {
        let (response, after) = route(request(cmd: "quit"))
        XCTAssertEqual(response["ok"] as? Bool, true)
        XCTAssertEqual(after, .terminate)
    }

    // MARK: get/set require key/value

    func testMissingKeyAndValueAreUsageErrors() {
        let (noKey, _) = route(["v": CommandRouter.protocolVersion, "cmd": "get"])
        XCTAssertEqual(noKey["ok"] as? Bool, false)
        let (noValue, _) = route(["v": CommandRouter.protocolVersion, "cmd": "set", "key": "enabled"])
        XCTAssertEqual(noValue["ok"] as? Bool, false)
    }
}
