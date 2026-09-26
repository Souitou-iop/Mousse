import Foundation
import Darwin
import AppKit

/// In-app command server backing the local CLI (see `CLICommand`). A Unix-domain socket in the
/// app's own Application Support directory answers one JSON request per connection on a dedicated
/// accept thread.
///
/// Ownership stays exactly where it was: this server owns NO engine state. Every command is
/// answered by `AppCommandDelegate`, which hops to the main thread for `ConfigStore` and reads
/// engine snapshots through the engine's own lock. The event tap, animator, pointer manager and
/// config write path therefore remain single-owner (the GUI process) by construction — a CLI
/// invocation is a short-lived client process, never a second engine.
///
/// The socket registers nothing with the system (no launchd, no login item): it is a file in the
/// user's directory with mode 0600, created while the app runs and unlinked on quit. A stale file
/// left by a crash is probed and replaced at startup; a socket owned by a LIVE peer is respected
/// (this instance declines to serve rather than fighting over it).
final class CommandServer {

    static let shared = CommandServer(path: CommandServer.defaultPath(), delegate: AppCommandDelegate())

    /// Mirrors ConfigStore's Application Support directory (same dir as config.json). Kept
    /// self-contained: ConfigStore is @MainActor-isolated and this must be callable before and
    /// without touching the main-actor world.
    static func defaultPath() -> String {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Mousse", isDirectory: true)
            .appendingPathComponent("mousse.sock").path
    }

    /// Full client round trip: connect, send one JSON request (newline-terminated), read the one
    /// JSON response. Returns nil when the app isn't running, the request is unencodable, or the
    /// exchange times out. Shared by the CLI, smoke checks and tests.
    static func request(path: String, payload: [String: Any], timeout: Double) -> [String: Any]? {
        guard JSONSerialization.isValidJSONObject(payload),
              var data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        data.append(UInt8(ascii: "\n"))
        let fd = tryConnect(path: path)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        applyTimeouts(fd: fd, seconds: timeout)
        guard sendAll(data, fd: fd) else { return nil }
        var received = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while received.count < 1_048_576 {
            let n = recv(fd, &chunk, chunk.count, 0)
            guard n > 0 else { break }
            received.append(contentsOf: chunk[0..<n])
            if received.last == UInt8(ascii: "\n") { break }
        }
        return (try? JSONSerialization.jsonObject(with: received)) as? [String: Any]
    }

    private let path: String
    private let delegate: CommandRouter.Delegate
    private var listenFD: Int32 = -1
    private let lock = NSLock() // guards listenFD (stop vs. the accept thread)

    init(path: String, delegate: CommandRouter.Delegate) {
        self.path = path
        self.delegate = delegate
    }

    /// Bind and serve. Idempotent, called once at app launch on the main thread.
    func start() {
        do {
            try FileManager.default.createDirectory(
                atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        } catch {
            NSLog("Mousse: could not create command-socket directory: \(error.localizedDescription)")
            return
        }
        // A leftover socket file: probe it. A live peer wins (never two servers); anything
        // unconnectable is crash debris and gets replaced.
        if FileManager.default.fileExists(atPath: path) {
            let probe = CommandServer.tryConnect(path: path)
            if probe >= 0 { close(probe) }
            if probe >= 0 {
                NSLog("Mousse: another instance owns the command socket; CLI not served here")
                return
            }
            unlink(path)
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { NSLog("Mousse: command socket() failed"); return }
        CommandServer.suppressSIGPIPE(fd: fd)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8) // String.withUTF8 is mutating; copy the view instead
        let fits = withUnsafeMutableBytes(of: &addr.sun_path) { dest -> Bool in
            guard bytes.count + 1 <= dest.count else { return false } // + NUL
            dest.copyBytes(from: bytes)
            dest[bytes.count] = 0
            return true
        }
        guard fits else { close(fd); NSLog("Mousse: command socket path too long"); return }
        let bound = withUnsafePointer(to: &addr) { p -> Int32 in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.bind(fd, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else { close(fd); NSLog("Mousse: command socket bind failed"); return }
        chmod(path, 0o600) // user-only, defense in depth beyond the directory's permissions
        guard listen(fd, 4) == 0 else { close(fd); NSLog("Mousse: command socket listen failed"); return }
        lock.lock(); listenFD = fd; lock.unlock()
        let thread = Thread { [weak self] in self?.acceptLoop(fd: fd) }
        thread.name = "com.mousse.command-server"
        thread.start()
    }

    /// Unlink and close. On macOS closing an fd another thread blocks in accept() on does not
    /// reliably wake it — the thread lingers until process exit, which is exactly when stop() is
    /// called (applicationWillTerminate). The unlink is what matters to the outside world.
    func stop() {
        lock.lock(); let fd = listenFD; listenFD = -1; lock.unlock()
        unlink(path)
        if fd >= 0 { close(fd) }
    }

    // MARK: Internals

    private func acceptLoop(fd: Int32) {
        while true {
            let conn = Darwin.accept(fd, nil, nil)
            guard conn >= 0 else { break } // fd closed by stop(), or a fatal accept error
            // One worker thread per connection. `handle` blocks in recv() until the client sends
            // a full request or its 5 s timeout fires; doing that inline would let a single
            // half-open client stall every later `status`/`get`/`set`. The delegate stays the
            // only engine-touching path (it hops to the main thread), so parallel workers cannot
            // race the engine — they only answer sockets concurrently.
            let thread = Thread { [weak self] in
                guard let self else { close(conn); return }
                self.handle(connection: conn)
                close(conn)
            }
            thread.stackSize = 512 * 1024
            thread.start()
        }
    }

    private func handle(connection conn: Int32) {
        CommandServer.suppressSIGPIPE(fd: conn) // accepted sockets don't reliably inherit the listen fd's option
        CommandServer.applyTimeouts(fd: conn, seconds: 5)
        // Read exactly one request: first '\n' (or EOF / 8 KiB cap — a longer "request" is not one).
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 1024)
        var line: Data?
        while buffer.count <= 8192 {
            let n = recv(conn, &chunk, chunk.count, 0)
            guard n > 0 else { break }
            buffer.append(contentsOf: chunk[0..<n])
            if let nl = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                line = buffer.subdata(in: buffer.startIndex..<nl)
                break
            }
            if n < chunk.count { break } // client sent the object and hung up
        }
        let request = line.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        guard let request else {
            _ = send(["ok": false, "v": CommandRouter.protocolVersion,
                      "error": "invalid request: expected one JSON object terminated by a newline"], fd: conn)
            return
        }
        let (response, after) = CommandRouter.route(request, delegate: delegate)
        let delivered = send(response, fd: conn)
        // The reply must be in the client's hands before the process tears the socket down.
        if delivered, after == .terminate {
            Thread.sleep(forTimeInterval: 0.1)
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    // MARK: Socket primitives (shared with the CLI client)

    private static func tryConnect(path: String) -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return -1 }
        suppressSIGPIPE(fd: fd)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8) // String.withUTF8 is mutating; copy the view instead
        let fits = withUnsafeMutableBytes(of: &addr.sun_path) { dest -> Bool in
            guard bytes.count + 1 <= dest.count else { return false }
            dest.copyBytes(from: bytes)
            dest[bytes.count] = 0
            return true
        }
        guard fits else { close(fd); return -1 }
        let connected = withUnsafePointer(to: &addr) { p -> Int32 in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.connect(fd, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { close(fd); return -1 }
        return fd
    }

    private static func applyTimeouts(fd: Int32, seconds: Double) {
        var tv = timeval(tv_sec: time_t(seconds), tv_usec: Int32(seconds.truncatingRemainder(dividingBy: 1) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    /// A peer hanging up mid-exchange must surface as a failed `send`, not a SIGPIPE that
    /// kills the process — probes and short-lived clients make that a normal event.
    private static func suppressSIGPIPE(fd: Int32) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    private static func sendAll(_ data: Data, fd: Int32) -> Bool {
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
            var offset = 0
            while offset < raw.count {
                let n = Darwin.send(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset, 0)
                guard n > 0 else { return false }
                offset += n
            }
            return true
        }
    }

    /// Serialize + newline + full send. Server-side (instance method) only.
    private func send(_ object: [String: Any], fd: Int32) -> Bool {
        guard JSONSerialization.isValidJSONObject(object),
              var data = try? JSONSerialization.data(withJSONObject: object) else { return false }
        data.append(UInt8(ascii: "\n"))
        return CommandServer.sendAll(data, fd: fd)
    }
}

/// The production delegate: forwards every command to live app state on the main thread. The
/// engine snapshot call is itself lock-guarded and thread-safe; ConfigStore's @Published config
/// MUST be touched on main, and every `set` lands through the same property assignment the
/// Settings UI uses — so persistence (debounced save) and the live engine reload happen exactly
/// as if the user had moved the control by hand.
struct AppCommandDelegate: CommandRouter.Delegate {

    /// Runs `body` on the main thread synchronously (and tells the compiler so). The accept
    /// thread calls this for every state-touching command; main never blocks on this thread, so
    /// no deadlock is possible.
    private func onMain<T>(_ body: @MainActor () -> T) -> T {
        if Thread.isMainThread { return MainActor.assumeIsolated(body) }
        return DispatchQueue.main.sync { MainActor.assumeIsolated(body) }
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func healthName(_ health: EventTapHealth) -> String {
        switch health {
        case .waitingForPermission: return "waitingForPermission"
        case .initializing: return "initializing"
        case .healthy: return "healthy"
        case .recovering: return "recovering"
        case .failed: return "failed"
        }
    }

    func status() -> [String: Any] {
        onMain {
            let config = ConfigStore.shared.config
            let snap = EventTapEngine.shared.diagnosticsSnapshot()
            return [
                "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
                "pid": Int(ProcessInfo.processInfo.processIdentifier),
                "enabled": config.enabled,
                "scrollMode": config.scrollMode.rawValue,
                "scrollSmoothness": config.scrollSmoothness.rawValue,
                "scrollSpeed": config.scrollSpeed,
                "zoomSpeed": config.zoomSpeed,
                "reverseScroll": config.reverseScroll,
                "accessibilityTrusted": snap.accessibilityTrusted,
                "inputMonitoringTrusted": snap.inputMonitoringTrusted,
                "eventTapHealth": AppCommandDelegate.healthName(snap.eventTapHealth),
                "recoveryCount": snap.recoveryCount,
                "mice": snap.detectedMice.map(\.name),
            ] as [String: Any]
        }
    }

    func diagnostics() -> [String: Any] {
        onMain {
            let snap = EventTapEngine.shared.diagnosticsSnapshot()
            var payload: [String: Any] = [
                "accessibilityTrusted": snap.accessibilityTrusted,
                "inputMonitoringTrusted": snap.inputMonitoringTrusted,
                "engineEnabled": snap.engineEnabled,
                "eventTapHealth": AppCommandDelegate.healthName(snap.eventTapHealth),
                "recoveryCount": snap.recoveryCount,
                "mice": snap.detectedMice.map { ["id": $0.id, "name": $0.name] },
            ]
            if let at = snap.lastRecoveryAt { payload["lastRecoveryAt"] = AppCommandDelegate.iso.string(from: at) }
            if let pointer = snap.pointerBundleID { payload["pointerBundleID"] = pointer }
            if let last = snap.lastAction {
                payload["lastAction"] = [
                    "button": last.button,
                    "action": String(describing: last.action),
                    "triggeredAt": AppCommandDelegate.iso.string(from: last.triggeredAt),
                ] as [String: Any]
            }
            return payload
        }
    }

    func get(key: String) -> CommandRouter.ConfigValue? {
        onMain {
            let config = ConfigStore.shared.config
            switch key {
            case "enabled":            return .bool(config.enabled)
            case "reverseScroll":      return .bool(config.reverseScroll)
            case "scrollAcceleration": return .bool(config.scrollAcceleration)
            case "smoothHighRes":      return .bool(config.smoothHighRes)
            case "edgeScroll":         return .bool(config.edgeScroll)
            case "scrollSpeed":        return .number(config.scrollSpeed)
            case "zoomSpeed":          return .number(config.zoomSpeed)
            case "edgeScrollSpeed":    return .number(config.edgeScrollSpeed)
            case "scrollMode":         return .string(config.scrollMode.rawValue)
            case "scrollSmoothness":   return .string(config.scrollSmoothness.rawValue)
            default:                   return nil
            }
        }
    }

    func set(key: String, value: CommandRouter.ConfigValue) -> Bool {
        onMain {
            switch (key, value) {
            case ("enabled", .bool(let v)):            ConfigStore.shared.config.enabled = v
            case ("reverseScroll", .bool(let v)):      ConfigStore.shared.config.reverseScroll = v
            case ("scrollAcceleration", .bool(let v)): ConfigStore.shared.config.scrollAcceleration = v
            case ("smoothHighRes", .bool(let v)):      ConfigStore.shared.config.smoothHighRes = v
            case ("edgeScroll", .bool(let v)):         ConfigStore.shared.config.edgeScroll = v
            case ("scrollSpeed", .number(let v)):      ConfigStore.shared.config.scrollSpeed = v
            case ("zoomSpeed", .number(let v)):        ConfigStore.shared.config.zoomSpeed = v
            case ("edgeScrollSpeed", .number(let v)):  ConfigStore.shared.config.edgeScrollSpeed = v
            case ("scrollMode", .string(let v)):
                guard let mode = ScrollMode(rawValue: v) else { return false }
                ConfigStore.shared.config.scrollMode = mode
            case ("scrollSmoothness", .string(let v)):
                guard let smoothness = ScrollSmoothness(rawValue: v) else { return false }
                ConfigStore.shared.config.scrollSmoothness = smoothness
            default:
                return false
            }
            return true
        }
    }
}
