import Foundation

enum EventTapHealth: Equatable, Sendable {
    case waitingForPermission
    case initializing
    case healthy
    case recovering
    case failed

    static func resolve(accessibilityTrusted: Bool, hasTap: Bool, tapEnabled: Bool,
                        rebuildPending: Bool, creationFailed: Bool,
                        lastRecoveryAt: Date?, now: Date) -> EventTapHealth {
        guard accessibilityTrusted else { return .waitingForPermission }
        if creationFailed { return .failed }
        guard hasTap else { return .initializing }
        if rebuildPending { return .recovering }
        let recentlyRecovered = lastRecoveryAt.map { now.timeIntervalSince($0) < 2 } ?? false
        return tapEnabled && !recentlyRecovered ? .healthy : .recovering
    }
}

struct DetectedMouse: Identifiable, Equatable, Sendable {
    let id: String
    let name: String

    static func deduplicated(_ mice: [DetectedMouse]) -> [DetectedMouse] {
        var byID: [String: DetectedMouse] = [:]
        for mouse in mice { byID[mouse.id] = mouse }
        return byID.values.sorted {
            let order = $0.name.localizedCaseInsensitiveCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }
}

struct LastTriggeredAction: Equatable, Sendable {
    let action: RemapAction
    let button: Int
    let triggeredAt: Date

    static func latest(in output: ButtonTriggerRecognizer.Output, at date: Date)
        -> LastTriggeredAction? {
        output.triggered.last.map {
            LastTriggeredAction(action: $0.action, button: $0.button, triggeredAt: date)
        }
    }
}

/// One aggregate entry per distinct scroll-event origin seen by the safety bypass.
struct InjectedScrollSourceSample: Equatable, Sendable {
    let sourceStateID: Int64
    let sourceProcessID: Int64
    var processName: String?
    var count: Int
    var lastAt: Date
}

/// Records wheel events classified as remotely injected, keyed by (source state, posting PID).
/// Owned by the event tap's lock; pure so tests drive it without the engine.
struct ScrollSourceLedger: Equatable, Sendable {
    static let sampleLimit = 8

    private(set) var totalCount = 0
    private(set) var lastAt: Date?
    private(set) var samples: [InjectedScrollSourceSample] = []

    /// The two CGEvent fields that identify an injected wheel event. Hardware input comes from the
    /// HID system state (state ID 1) with no posting process; anything violating BOTH — a remote
    /// control client posting over the combined/private session state — is injected.
    static func isInjected(sourceStateID: Int64, sourceProcessID: Int64,
                           hardwareStateID: Int64) -> Bool {
        sourceStateID != hardwareStateID && sourceProcessID != 0
    }

    /// `processName` is resolved once per PID by the caller (proc_pidpath is a syscall — keep it
    /// off the per-event path when the source repeats).
    mutating func record(sourceStateID: Int64, sourceProcessID: Int64,
                         processName: String?, at now: Date) {
        totalCount += 1
        lastAt = now
        if let index = samples.firstIndex(where: { $0.sourceStateID == sourceStateID
            && $0.sourceProcessID == sourceProcessID }) {
            samples[index].count += 1
            samples[index].lastAt = now
            if samples[index].processName == nil { samples[index].processName = processName }
        } else {
            let sample = InjectedScrollSourceSample(sourceStateID: sourceStateID,
                                                    sourceProcessID: sourceProcessID,
                                                    processName: processName, count: 1, lastAt: now)
            if samples.count >= Self.sampleLimit {
                if let oldest = samples.indices.min(by: { samples[$0].lastAt < samples[$1].lastAt }) {
                    samples.remove(at: oldest)
                }
            }
            samples.append(sample)
        }
    }
}

struct EngineDiagnosticsSnapshot: Equatable, Sendable {
    let accessibilityTrusted: Bool
    let inputMonitoringTrusted: Bool
    let engineEnabled: Bool
    let eventTapHealth: EventTapHealth
    let recoveryCount: Int
    let lastRecoveryAt: Date?
    let detectedMice: [DetectedMouse]
    let pointerBundleID: String?
    let lastAction: LastTriggeredAction?
    let injectedScrollLedger: ScrollSourceLedger
    let wheelEventCount: Int
    let unusualHardwareLedger: ScrollSourceLedger
}
