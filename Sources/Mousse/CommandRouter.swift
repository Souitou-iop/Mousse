import Foundation

/// Pure command protocol + dispatch for the local command socket (see `CommandServer` and
/// `CLICommand`). One JSON object per connection, terminated by a newline:
///
///     request:  {"v": 1, "cmd": "status" | "diagnostics" | "get" | "set" | "quit",
///                "key": "...", "value": ...}          (key/value only for get/set)
///     response: {"ok": true,  "v": 1, ...payload}  or  {"ok": false, "v": 1, "error": "..."}
///
/// Routing, key whitelisting and value coercion are pure and unit-tested; the delegate is the
/// thin bridge into live app state (main thread, engine snapshots). The `set` surface is a
/// fixed whitelist of scalar config keys — never mappings or opaque blobs — so an AI client
/// cannot write a config the engine can't make sense of.
enum CommandRouter {

    /// A validated scalar config value, tagged by kind so the delegate can assign it safely.
    enum ConfigValue: Equatable {
        case bool(Bool)
        case number(Double)
        case string(String)

        var jsonValue: Any {
            switch self {
            case .bool(let b): return b
            case .number(let n): return n
            case .string(let s): return s
            }
        }
    }

    /// What the caller must do AFTER the reply has been delivered to the client.
    enum PostReplyAction: Equatable { case terminate }

    /// The data side of the commands. Implemented by the app (`AppCommandDelegate`, which hops to
    /// the main thread) and by tests with canned state.
    protocol Delegate {
        /// Engine + permission summary (payload only; `ok`/`v` are added by the router).
        func status() -> [String: Any]
        /// Full diagnostics snapshot as a JSON-safe payload.
        func diagnostics() -> [String: Any]
        /// Current value for a whitelisted key, or nil when the key is unknown.
        func get(key: String) -> ConfigValue?
        /// Assign a validated value. Returning false means the delegate rejected it (type/field
        /// mismatch) — the router has already validated the same table, so this is a backstop.
        func set(key: String, value: ConfigValue) -> Bool
    }

    static let protocolVersion = 1

    // MARK: Key whitelist (single source of truth for get/set and the CLI help text)

    private static let boolKeys: Set<String> = [
        "enabled", "reverseScroll", "reverseScrollHorizontal", "scrollAcceleration", "smoothHighRes", "edgeScroll",
    ]
    private static let numberKeys: [String: ClosedRange<Double>] = [
        "scrollSpeed": 0.05...3.0,
        "zoomSpeed": 0.2...6.0,
        "edgeScrollSpeed": 50.0...2400.0,
    ]
    private static let enumKeys: [String: Set<String>] = [
        "scrollMode": ["native", "standard", "smooth", "smoothStep"],
        "scrollSmoothness": ["snappy", "balanced", "floaty"],
    ]

    /// All keys accepted by get/set, sorted — surfaced verbatim in `Mousse help`.
    static var supportedKeys: [String] {
        (Array(boolKeys) + Array(numberKeys.keys) + Array(enumKeys.keys)).sorted()
    }

    /// Per-key help lines (name, kind, allowed values/range) for the CLI usage text.
    static var keysHelp: String {
        var lines: [String] = []
        for key in supportedKeys {
            if boolKeys.contains(key) {
                lines.append("  \(key.padding(toLength: max(20, key.count + 1), withPad: " ", startingAt: 0))true | false")
            } else if let range = numberKeys[key] {
                lines.append("  \(key.padding(toLength: max(20, key.count + 1), withPad: " ", startingAt: 0))number in [\(range.lowerBound), \(range.upperBound)]")
            } else {
                lines.append("  \(key.padding(toLength: max(20, key.count + 1), withPad: " ", startingAt: 0))\((enumKeys[key] ?? []).sorted().joined(separator: " | "))")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Dispatch

    static func route(_ request: [String: Any], delegate: Delegate)
        -> (response: [String: Any], after: PostReplyAction?) {

        func error(_ message: String) -> (response: [String: Any], after: PostReplyAction?) {
            (["ok": false, "v": protocolVersion, "error": message], nil)
        }
        func wrap(_ payload: [String: Any]) -> [String: Any] {
            var response = payload
            response["ok"] = true
            response["v"] = protocolVersion
            return response
        }

        // JSON integers arrive as NSNumber; `as? Int` bridges them. A missing "v" is rejected
        // (not defaulted): a client that forgot the version is a client worth telling.
        // JSON `true` bridges to NSNumber(1), so `as? Int` would accept `{"v": true}` as
        // version 1. A real version must be an integer, not a boolean.
        guard !CommandRouter.isJSONBool(request["v"] as Any),
              (request["v"] as? Int) == protocolVersion else {
            return error("unsupported protocol version (expected \(protocolVersion))")
        }
        guard let cmd = request["cmd"] as? String else {
            return error("missing command string 'cmd'")
        }

        switch cmd {
        case "status":
            return (wrap(delegate.status()), nil)
        case "diagnostics":
            return (wrap(delegate.diagnostics()), nil)
        case "get":
            guard let key = request["key"] as? String else { return error("missing 'key'") }
            guard let value = delegate.get(key: key) else {
                return error("unknown key: \(key) — see 'Mousse help'")
            }
            return (wrap(["key": key, "value": value.jsonValue]), nil)
        case "set":
            guard let key = request["key"] as? String else { return error("missing 'key'") }
            guard let raw = request["value"] else { return error("missing 'value'") }
            guard let value = coerce(raw, for: key) else { return error(coercionHint(for: key)) }
            guard delegate.set(key: key, value: value) else {
                return error("value rejected by the app for key: \(key)")
            }
            return (wrap(["key": key, "value": value.jsonValue]), nil)
        case "quit":
            return (wrap(["note": "Mousse is terminating"]), .terminate)
        default:
            return error("unknown command: \(cmd) — see 'Mousse help'")
        }
    }

    // MARK: Value coercion

    /// JSON booleans bridge through NSNumber, so `1 as? Bool` is `true` — a plain cast would
    /// silently accept `{"value": 5}` for a bool key. True booleans are recognized exactly via
    /// the CFBoolean type ID; everything else is a number/string and rejected for bool keys.
    static func isJSONBool(_ value: Any) -> Bool {
        (value as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
    }

    private static func coerce(_ raw: Any, for key: String) -> ConfigValue? {
        if boolKeys.contains(key) {
            guard isJSONBool(raw), let b = raw as? Bool else { return nil }
            return .bool(b)
        }
        if let range = numberKeys[key] {
            // Through NSNumber, not `as? Double`: a JSON integer and a Swift-native Int literal
            // both bridge, while a native Int in Any would fail a direct Double cast.
            guard !isJSONBool(raw), let n = (raw as? NSNumber)?.doubleValue, range.contains(n) else { return nil }
            return .number(n)
        }
        if let allowed = enumKeys[key] {
            guard let s = raw as? String, allowed.contains(s) else { return nil }
            return .string(s)
        }
        return nil
    }

    /// The rejection message doubles as documentation of what WOULD be accepted.
    private static func coercionHint(for key: String) -> String {
        if boolKeys.contains(key) { return "'\(key)' expects true or false" }
        if let range = numberKeys[key] {
            return "'\(key)' expects a number in [\(range.lowerBound), \(range.upperBound)]"
        }
        if let allowed = enumKeys[key] {
            return "'\(key)' expects one of: \(allowed.sorted().joined(separator: ", "))"
        }
        return "unknown key: \(key) — see 'Mousse help'"
    }
}
