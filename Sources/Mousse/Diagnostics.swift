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
}
