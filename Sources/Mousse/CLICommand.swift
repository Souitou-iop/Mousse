import Foundation

/// Thin CLI client: `Mousse status | diagnostics | get <key> | set <key> <value> | quit | help`.
///
/// Runs from `MousseEntry.main` BEFORE any AppKit/SwiftUI startup: this process owns no engine
/// state, creates no event tap, and registers nothing. It forwards one JSON request to the
/// running app over the command socket (`CommandServer`), prints the JSON reply, and exits.
/// Exit codes: 0 success, 1 failure (app not running / server reported an error), 2 usage error.
///
/// Machine-facing by design: every reply is a single JSON object, and `Mousse help` documents the
/// whole surface so an agent can discover it without external docs.
enum CLICommand {

    /// Called first thing in `main`. CLI-shaped first arguments run here and exit; anything else
    /// falls through into the GUI app (the binary is both the menu-bar app and the CLI client).
    static func runIfRequested(_ argv: [String]) {
        guard argv.count >= 2 else { return }
        switch argv[1].lowercased() {
        case "help", "-h", "--help", "version", "--version", "-v",
             "status", "diagnostics", "get", "set", "quit":
            exit(run(argv))
        default:
            return // not a CLI invocation — launch the GUI
        }
    }

    static func run(_ argv: [String]) -> Int32 {
        let cmd = argv[1].lowercased()
        switch cmd {
        case "help", "-h", "--help":
            print(helpText)
            return 0
        case "version", "--version", "-v":
            print(versionText)
            return 0
        case "status":
            return send(["cmd": "status"])
        case "diagnostics":
            return send(["cmd": "diagnostics"])
        case "quit":
            return send(["cmd": "quit"])
        case "get":
            guard argv.count == 3 else { return usageError("get requires exactly one <key>") }
            return send(["cmd": "get", "key": argv[2]])
        case "set":
            guard argv.count == 4 else { return usageError("set requires exactly <key> <value>") }
            guard let value = parseValue(argv[3]) else {
                return usageError("cannot parse value: '\(argv[3])' (use true/false, a number, or a bare string)")
            }
            return send(["cmd": "set", "key": argv[2], "value": value])
        default:
            return 2 // unreachable: runIfRequested only forwards known commands
        }
    }

    // MARK: Parsing

    /// CLI value grammar: true/false (any case) → bool; anything Double() accepts → number;
    /// anything else travels as a string (enum keys such as scrollMode). The server side
    /// validates against the key whitelist — the CLI never second-guesses the schema.
    private static func parseValue(_ raw: String) -> Any? {
        switch raw.lowercased() {
        case "true": return true
        case "false": return false
        default: break
        }
        // Reject non-finite numbers ("nan", "inf", "1e309"): Double() accepts them, but
        // JSONSerialization rejects them, so they would otherwise surface as a bogus
        // "Mousse is not running" transport error instead of a usage error.
        if let d = Double(raw), d.isFinite { return d }
        return raw
    }

    // MARK: Transport + output

    private static func send(_ request: [String: Any]) -> Int32 {
        var payload = request
        payload["v"] = CommandRouter.protocolVersion
        guard let response = CommandServer.request(path: CommandServer.defaultPath(),
                                                   payload: payload, timeout: 5) else {
            FileHandle.standardError.write(Data(
                "error: Mousse is not running (no command socket at \(CommandServer.defaultPath())).\n".utf8))
            return 1
        }
        let pretty = (try? JSONSerialization.data(withJSONObject: response,
                                                  options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
        print(String(data: pretty, encoding: .utf8) ?? "{}")
        return (response["ok"] as? Bool) == true ? 0 : 1
    }

    private static func usageError(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data("error: \(message)\n\n\(helpText)\n".utf8))
        return 2
    }

    private static var versionText: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    // MARK: Help (the discoverability surface — keep in sync with the router, which owns the table)

    static var helpText: String {
        """
        Mousse — local command-line interface

        USAGE
          Mousse <command> [arguments]

        COMMANDS
          status                     engine + permission summary (JSON)
          diagnostics                full diagnostics snapshot (JSON)
          get <key>                  read one config value (JSON)
          set <key> <value>          change one config value (JSON reply; applied live)
          quit                       ask the running app to terminate gracefully
          help                       this text
          --version                  app version

        CONFIG KEYS (set <key> <value>)
        \(CommandRouter.keysHelp)

        EXAMPLES
          Mousse status
          Mousse set scrollMode smooth
          Mousse set scrollSpeed 0.5
          Mousse set enabled false

        NOTES
          - Every reply is one JSON object; exit code 0 = ok, 1 = error, 2 = usage.
          - Commands act on the RUNNING app instance (it must be running; nothing is spawned).
          - `set` writes through the same path as the Settings UI: live reload + persisted config.
        """
    }
}
