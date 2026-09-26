import XCTest
import Foundation
import Darwin
@testable import Mousse

/// Real socket round trip: a `CommandServer` on a temp path, driven through the same
/// `CommandServer.request` client the CLI uses. Covers framing (newline-terminated JSON),
/// live get/set against a delegate, and startup recovery from a stale socket file.
final class CommandSocketTests: XCTestCase {

    private final class RecordingDelegate: CommandRouter.Delegate {
        var statusPayload: [String: Any] = ["engine": "test"]
        private(set) var written: [(key: String, value: CommandRouter.ConfigValue)] = []
        var values: [String: CommandRouter.ConfigValue] = ["scrollSpeed": .number(0.3)]

        func status() -> [String: Any] { statusPayload }
        func diagnostics() -> [String: Any] { ["recoveryCount": 0] }
        func get(key: String) -> CommandRouter.ConfigValue? { values[key] }
        func set(key: String, value: CommandRouter.ConfigValue) -> Bool {
            written.append((key, value))
            values[key] = value
            return true
        }
    }

    private var paths: [String] = []

    override func tearDown() {
        for path in paths { unlink(path) }
        paths.removeAll()
        super.tearDown()
    }

    private func makePath() -> String {
        let path = NSTemporaryDirectory() + "mousse-test-\(UUID().uuidString).sock"
        paths.append(path)
        return path
    }

    private func request(_ payload: [String: Any], path: String) -> [String: Any]? {
        CommandServer.request(path: path, payload: payload, timeout: 5)
    }

    private func envelope(_ payload: [String: Any]) -> [String: Any] {
        var p = payload
        p["v"] = CommandRouter.protocolVersion
        return p
    }

    func testRoundTripStatusGetSet() throws {
        let delegate = RecordingDelegate()
        let server = CommandServer(path: makePath(), delegate: delegate)
        server.start()

        // status
        let status = try XCTUnwrap(request(envelope(["cmd": "status"]), path: paths[0]))
        XCTAssertEqual(status["ok"] as? Bool, true)
        XCTAssertEqual(status["engine"] as? String, "test")

        // get
        let got = try XCTUnwrap(request(envelope(["cmd": "get", "key": "scrollSpeed"]), path: paths[0]))
        XCTAssertEqual(got["value"] as? Double, 0.3)

        // set (the router coerces the JSON int into .number(1.0) before the delegate sees it)
        let set = try XCTUnwrap(request(envelope(["cmd": "set", "key": "scrollSpeed", "value": 1]), path: paths[0]))
        XCTAssertEqual(set["ok"] as? Bool, true)
        XCTAssertEqual(delegate.written.last?.value, .number(1.0))
        let reread = try XCTUnwrap(request(envelope(["cmd": "get", "key": "scrollSpeed"]), path: paths[0]))
        XCTAssertEqual(reread["value"] as? Double, 1.0, "the delegate must observe the write")

        // server-reported error (unknown key) crosses the socket intact
        let bad = try XCTUnwrap(request(envelope(["cmd": "get", "key": "nope"]), path: paths[0]))
        XCTAssertEqual(bad["ok"] as? Bool, false)
    }

    func testInvalidRequestGetsAJSONErrorBack() throws {
        let server = CommandServer(path: makePath(), delegate: RecordingDelegate())
        server.start()
        // Raw socket, garbage payload — must still be answered with the protocol error object.
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(paths[0].utf8) // String.withUTF8 is mutating; copy the view instead
        withUnsafeMutableBytes(of: &addr.sun_path) { dest in
            dest.copyBytes(from: bytes)
            dest[bytes.count] = 0
        }
        let connected = withUnsafePointer(to: &addr) { p -> Int32 in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.connect(fd, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        XCTAssertEqual(connected, 0)
        let junk = Data("not json at all\n".utf8)
        _ = junk.withUnsafeBytes { raw in send(fd, raw.baseAddress, raw.count, 0) }
        var received = Data()
        var chunk = [UInt8](repeating: 0, count: 1024)
        for _ in 0..<50 {
            let n = recv(fd, &chunk, chunk.count, 0)
            guard n > 0 else { break }
            received.append(contentsOf: chunk[0..<n])
            if received.last == UInt8(ascii: "\n") { break }
        }
        let response = try XCTUnwrap((try? JSONSerialization.jsonObject(with: received)) as? [String: Any])
        XCTAssertEqual(response["ok"] as? Bool, false)
        XCTAssertTrue((response["error"] as? String)?.contains("invalid request") ?? false)
    }

    func testStaleSocketFileIsReplacedLiveOneIsRespected() throws {
        // Stale: a plain file where the socket should be — the server replaces it and serves.
        let stalePath = makePath()
        try Data("debris".utf8).write(to: URL(fileURLWithPath: stalePath))
        let server = CommandServer(path: stalePath, delegate: RecordingDelegate())
        server.start()
        let status = try XCTUnwrap(request(envelope(["cmd": "status"]), path: stalePath))
        XCTAssertEqual(status["ok"] as? Bool, true, "stale file must be unlinked and re-bound")

        // Live: an actual listener is already owned elsewhere — the second server must decline
        // to serve rather than steal the socket file.
        let livePath = makePath()
        let live = CommandServer(path: livePath, delegate: RecordingDelegate())
        live.start()
        let second = CommandServer(path: livePath, delegate: RecordingDelegate())
        second.start() // must NOT unlink the live socket
        let stillLive = try XCTUnwrap(request(envelope(["cmd": "status"]), path: livePath))
        XCTAssertEqual(stillLive["engine"] as? String, "test",
                       "the original server must still own the socket")
        _ = second // declined; nothing further to assert beyond the socket surviving
    }

    /// A stalled (half-open) client must not block other clients: the accept loop dispatches each
    /// connection to its own worker, so a follow-up request is answered without waiting for the
    /// stalled one's 5 s timeout.
    func testStalledClientDoesNotBlockOtherRequests() throws {
        let server = CommandServer(path: makePath(), delegate: RecordingDelegate())
        server.start()

        // Connect and send nothing — the worker blocks in recv().
        let stalled = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(stalled, 0)
        defer { close(stalled) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(paths[0].utf8)
        withUnsafeMutableBytes(of: &addr.sun_path) { dest in
            dest.copyBytes(from: bytes)
            dest[bytes.count] = 0
        }
        let connected = withUnsafePointer(to: &addr) { p -> Int32 in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.connect(stalled, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        XCTAssertEqual(connected, 0)
        Thread.sleep(forTimeInterval: 0.2) // let the accept loop hand it to a worker

        let started = Date()
        let status = try XCTUnwrap(request(envelope(["cmd": "status"]), path: paths[0]))
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertEqual(status["ok"] as? Bool, true, "a second client must still be served")
        XCTAssertLessThan(elapsed, 2.0, "must not wait for the stalled client's 5 s timeout")
    }

    func testClientGetsNilWhenAppIsNotRunning() {
        let missing = makePath() // never bound
        let result = request(envelope(["cmd": "status"]), path: missing)
        XCTAssertNil(result, "no server → connect fails → nil, which the CLI turns into exit 1")
    }
}
