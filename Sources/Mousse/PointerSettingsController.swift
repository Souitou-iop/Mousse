import AppKit
import Combine
import Foundation
import IOKit.hid
import MousseHIDBridge

enum PointerHIDProperty: Hashable {
    case linearAcceleration
    case pointerResolution
}

protocol PointerHIDBackend: AnyObject {
    var isAvailable: Bool { get }
    func deviceIDs() -> [UInt64]
    func read(_ property: PointerHIDProperty, deviceID: UInt64) -> Int64?
    @discardableResult
    func write(_ value: Int64, property: PointerHIDProperty, deviceID: UInt64) -> Bool
}

final class SystemPointerHIDBackend: PointerHIDBackend {
    private let client: OpaquePointer?

    init() {
        client = MousseHIDClientCreate()
    }

    deinit {
        if let client {
            MousseHIDClientDestroy(client)
        }
    }

    var isAvailable: Bool { client != nil }

    func deviceIDs() -> [UInt64] {
        guard let client else { return [] }
        var rawIDs: UnsafeMutablePointer<UInt64>?
        let count = MousseHIDClientCopyDeviceIDs(
            client, &rawIDs)
        guard count > 0, let rawIDs else { return [] }
        defer { MousseHIDDeviceIDsDestroy(rawIDs) }
        return Array(UnsafeBufferPointer(start: rawIDs, count: count))
    }

    func read(_ property: PointerHIDProperty, deviceID: UInt64) -> Int64? {
        guard let client else { return nil }
        var value: Int64 = 0
        guard MousseHIDClientReadInt64(
            client, deviceID,
            property.bridgeValue, &value) else { return nil }
        return value
    }

    func write(_ value: Int64, property: PointerHIDProperty, deviceID: UInt64) -> Bool {
        guard let client else { return false }
        return MousseHIDClientWriteInt64(
            client, deviceID,
            property.bridgeValue, value)
    }
}

private extension PointerHIDProperty {
    var bridgeValue: MousseHIDProperty {
        switch self {
        case .linearAcceleration: return MousseHIDPropertyLinearAcceleration
        case .pointerResolution: return MousseHIDPropertyPointerResolution
        }
    }
}

struct PointerSettingsTarget: Equatable, Sendable {
    let accelerationEnabled: Bool
    let speedMultiplier: Double
    let matchedProfileBundleID: String?
}

enum PointerSettingsResolver {
    static func resolve(config: AppConfig, frontmostBundleID: String?) -> PointerSettingsTarget? {
        guard config.enabled, config.pointerControlEnabled else { return nil }
        let profile = frontmostBundleID.flatMap { bundleID in
            config.pointerAppProfiles.last { $0.bundleID == bundleID }
        }
        let accelerationEnabled: Bool
        switch profile?.acceleration ?? .inherit {
        case .inherit: accelerationEnabled = config.pointerAccelerationEnabled
        case .enabled: accelerationEnabled = true
        case .disabled: accelerationEnabled = false
        }
        return PointerSettingsTarget(
            accelerationEnabled: accelerationEnabled,
            speedMultiplier: PointerSpeedSetting.clamp(
                profile?.speedMultiplier ?? config.pointerSpeedMultiplier),
            matchedProfileBundleID: profile?.bundleID)
    }
}

enum PointerApplyHealth: Equatable, Sendable {
    case inactive
    case applied
    case unavailable
    case failed
    case drifted
}

enum PointerFailureReason: Equatable, Sendable {
    case serviceUnavailable
    case noMouse
    case baselineReadFailed
    case writeFailed
    case restoreFailed
    case externalChange
}

struct PointerDiagnosticsSnapshot: Equatable, Sendable {
    let managementEnabled: Bool
    let frontmostBundleID: String?
    let matchedProfileBundleID: String?
    let accelerationEnabled: Bool?
    let speedMultiplier: Double
    let actualAccelerationEnabled: Bool?
    let actualSpeedMultiplier: Double?
    let connectedDeviceCount: Int
    let appliedDeviceCount: Int
    let health: PointerApplyHealth
    let failureReason: PointerFailureReason?

    static let inactive = PointerDiagnosticsSnapshot(
        managementEnabled: false,
        frontmostBundleID: nil,
        matchedProfileBundleID: nil,
        accelerationEnabled: nil,
        speedMultiplier: 1,
        actualAccelerationEnabled: nil,
        actualSpeedMultiplier: nil,
        connectedDeviceCount: 0,
        appliedDeviceCount: 0,
        health: .inactive,
        failureReason: nil)
}

final class PointerSettingsEngine {
    private struct Baseline {
        var acceleration: Int64?
        var resolution: Int64?
    }

    private struct Expected {
        let acceleration: Int64
        let resolution: Int64
    }

    private static let fixedScale = 65_536.0
    private static let resolutionRange = 10.0...1_995.0

    private let backend: PointerHIDBackend
    private var baselines: [UInt64: Baseline] = [:]
    private var expected: [UInt64: Expected] = [:]
    private(set) var snapshot = PointerDiagnosticsSnapshot.inactive

    init(backend: PointerHIDBackend) {
        self.backend = backend
    }

    func apply(config: AppConfig, frontmostBundleID: String?) {
        guard let target = PointerSettingsResolver.resolve(
            config: config, frontmostBundleID: frontmostBundleID) else {
            restore(frontmostBundleID: frontmostBundleID)
            return
        }
        guard backend.isAvailable else {
            snapshot = makeSnapshot(
                target: target, frontmostBundleID: frontmostBundleID,
                deviceIDs: [], applied: 0, health: .unavailable,
                failureReason: .serviceUnavailable)
            return
        }

        let ids = Array(Set(backend.deviceIDs())).sorted()
        let currentIDs = Set(ids)
        baselines = baselines.filter { currentIDs.contains($0.key) }
        expected = expected.filter { currentIDs.contains($0.key) }
        guard !ids.isEmpty else {
            snapshot = makeSnapshot(
                target: target, frontmostBundleID: frontmostBundleID,
                deviceIDs: [], applied: 0, health: .unavailable,
                failureReason: .noMouse)
            return
        }

        // A system setting or another mouse utility may have changed one HID property since our
        // last successful write. Preserve only the changed property as the new restore baseline;
        // the untouched property must still restore to its original value.
        adoptExternalChangesAsBaseline()

        var applied = 0
        var failed = false
        var failureReason: PointerFailureReason?
        for id in ids {
            if baselines[id] == nil {
                baselines[id] = Baseline(
                    acceleration: backend.read(.linearAcceleration, deviceID: id),
                    resolution: backend.read(.pointerResolution, deviceID: id))
            }
            guard let baseline = baselines[id],
                  baseline.acceleration != nil,
                  let originalResolution = baseline.resolution,
                  originalResolution > 0 else {
                failed = true
                failureReason = failureReason ?? .baselineReadFailed
                continue
            }
            let targetAcceleration: Int64 = target.accelerationEnabled ? 0 : 1
            let targetResolution = Self.adjustedResolution(
                baselineRawValue: originalResolution,
                multiplier: target.speedMultiplier)
            let accelerationOK = setIfNeeded(
                targetAcceleration, property: .linearAcceleration, deviceID: id)
            let resolutionOK = setIfNeeded(
                targetResolution, property: .pointerResolution, deviceID: id)
            if accelerationOK && resolutionOK {
                expected[id] = Expected(
                    acceleration: targetAcceleration, resolution: targetResolution)
                applied += 1
            } else {
                expected.removeValue(forKey: id)
                failed = true
                failureReason = .writeFailed
            }
        }
        snapshot = makeSnapshot(
            target: target, frontmostBundleID: frontmostBundleID,
            deviceIDs: ids, applied: applied,
            health: failed ? .failed : .applied,
            failureReason: failureReason)
    }

    func restore(frontmostBundleID: String? = nil) {
        // This check also runs when the pointer page was never opened, so quitting or disabling
        // Mousse cannot overwrite a system-setting change that happened while we were managing.
        adoptExternalChangesAsBaseline()
        var failed = false
        for (id, baseline) in baselines {
            if let acceleration = baseline.acceleration,
               !setIfNeeded(acceleration, property: .linearAcceleration, deviceID: id) {
                failed = true
            }
            if let resolution = baseline.resolution,
               !setIfNeeded(resolution, property: .pointerResolution, deviceID: id) {
                failed = true
            }
        }
        baselines.removeAll()
        expected.removeAll()
        snapshot = PointerDiagnosticsSnapshot(
            managementEnabled: false,
            frontmostBundleID: frontmostBundleID,
            matchedProfileBundleID: nil,
            accelerationEnabled: nil,
            speedMultiplier: 1,
            actualAccelerationEnabled: nil,
            actualSpeedMultiplier: nil,
            connectedDeviceCount: backend.deviceIDs().count,
            appliedDeviceCount: 0,
            health: failed ? .failed : .inactive,
            failureReason: failed ? .restoreFailed : nil)
    }

    func refreshDiagnostics() -> PointerDiagnosticsSnapshot {
        guard snapshot.managementEnabled, snapshot.health != .unavailable else { return snapshot }
        let drifted = expected.contains { id, values in
            backend.read(.linearAcceleration, deviceID: id) != values.acceleration
                || backend.read(.pointerResolution, deviceID: id) != values.resolution
        }
        if drifted {
            adoptExternalChangesAsBaseline()
            let actual = actualState(deviceIDs: Array(expected.keys))
            snapshot = PointerDiagnosticsSnapshot(
                managementEnabled: snapshot.managementEnabled,
                frontmostBundleID: snapshot.frontmostBundleID,
                matchedProfileBundleID: snapshot.matchedProfileBundleID,
                accelerationEnabled: snapshot.accelerationEnabled,
                speedMultiplier: snapshot.speedMultiplier,
                actualAccelerationEnabled: actual.accelerationEnabled,
                actualSpeedMultiplier: actual.speedMultiplier,
                connectedDeviceCount: snapshot.connectedDeviceCount,
                appliedDeviceCount: snapshot.appliedDeviceCount,
                health: .drifted,
                failureReason: .externalChange)
        }
        return snapshot
    }

    private func adoptExternalChangesAsBaseline() {
        for (id, expectedValues) in expected {
            guard var baseline = baselines[id] else { continue }
            if let currentAcceleration = backend.read(.linearAcceleration, deviceID: id),
               currentAcceleration != expectedValues.acceleration,
               currentAcceleration != baseline.acceleration {
                baseline.acceleration = currentAcceleration
            }
            if let currentResolution = backend.read(.pointerResolution, deviceID: id),
               currentResolution > 0,
               currentResolution != expectedValues.resolution,
               currentResolution != baseline.resolution {
                baseline.resolution = currentResolution
            }
            baselines[id] = baseline
        }
    }

    static func adjustedResolution(baselineRawValue: Int64, multiplier: Double) -> Int64 {
        let baseline = Double(baselineRawValue) / fixedScale
        let adjusted = min(max(
            baseline / PointerSpeedSetting.clamp(multiplier),
            resolutionRange.lowerBound), resolutionRange.upperBound)
        return Int64((adjusted * fixedScale).rounded())
    }

    private func setIfNeeded(_ value: Int64, property: PointerHIDProperty,
                             deviceID: UInt64) -> Bool {
        if backend.read(property, deviceID: deviceID) == value { return true }
        guard backend.write(value, property: property, deviceID: deviceID) else { return false }
        return backend.read(property, deviceID: deviceID) == value
    }

    private func makeSnapshot(target: PointerSettingsTarget, frontmostBundleID: String?,
                              deviceIDs: [UInt64], applied: Int,
                              health: PointerApplyHealth,
                              failureReason: PointerFailureReason?) -> PointerDiagnosticsSnapshot {
        let actual = actualState(deviceIDs: deviceIDs)
        return PointerDiagnosticsSnapshot(
            managementEnabled: true,
            frontmostBundleID: frontmostBundleID,
            matchedProfileBundleID: target.matchedProfileBundleID,
            accelerationEnabled: target.accelerationEnabled,
            speedMultiplier: target.speedMultiplier,
            actualAccelerationEnabled: actual.accelerationEnabled,
            actualSpeedMultiplier: actual.speedMultiplier,
            connectedDeviceCount: deviceIDs.count,
            appliedDeviceCount: applied,
            health: health,
            failureReason: failureReason)
    }

    private func actualState(deviceIDs: [UInt64])
        -> (accelerationEnabled: Bool?, speedMultiplier: Double?) {
        guard !deviceIDs.isEmpty else { return (nil, nil) }
        var accelerationValues = Set<Bool>()
        var speedValues: [Double] = []
        for id in deviceIDs {
            guard let baseline = baselines[id],
                  let originalResolution = baseline.resolution,
                  originalResolution > 0,
                  let acceleration = backend.read(.linearAcceleration, deviceID: id),
                  let resolution = backend.read(.pointerResolution, deviceID: id),
                  resolution > 0 else { return (nil, nil) }
            accelerationValues.insert(acceleration == 0)
            speedValues.append(Double(originalResolution) / Double(resolution))
        }
        let roundedSpeeds = speedValues.map { ($0 * 100).rounded() / 100 }
        let firstSpeed = roundedSpeeds.first
        let speedsAgree = firstSpeed.map { first in
            roundedSpeeds.allSatisfy { abs($0 - first) < 0.01 }
        } ?? false
        return (
            accelerationValues.count == 1 ? accelerationValues.first : nil,
            speedsAgree ? firstSpeed : nil)
    }
}

@MainActor
final class PointerSettingsController: ObservableObject {
    static let shared = PointerSettingsController()

    @Published private(set) var snapshot = PointerDiagnosticsSnapshot.inactive

    private let engine: PointerSettingsEngine
    private var config = AppConfig()
    private var frontmostBundleID: String?
    private var started = false
    private var isSleeping = false
    private var hidManager: IOHIDManager?
    private var workspaceObservers: [NSObjectProtocol] = []

    init(backend: PointerHIDBackend = SystemPointerHIDBackend()) {
        engine = PointerSettingsEngine(backend: backend)
    }

    func start(config: AppConfig) {
        self.config = config
        guard !started else {
            applyCurrentSettings()
            return
        }
        started = true
        isSleeping = false
        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        installObservers()
        startDeviceMonitor()
        applyCurrentSettings()
    }

    func reload(_ config: AppConfig) {
        self.config = config
        guard started else { return }
        applyCurrentSettings()
    }

    func stopAndRestore() {
        engine.restore(frontmostBundleID: frontmostBundleID)
        snapshot = engine.snapshot
        if let hidManager {
            IOHIDManagerUnscheduleFromRunLoop(
                hidManager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(hidManager, IOOptionBits(kIOHIDOptionsTypeNone))
            self.hidManager = nil
        }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers { workspaceCenter.removeObserver(observer) }
        workspaceObservers.removeAll()
        started = false
        isSleeping = false
    }

    func diagnosticsSnapshot(refreshActual: Bool = false) -> PointerDiagnosticsSnapshot {
        if refreshActual { snapshot = engine.refreshDiagnostics() }
        return snapshot
    }

    func adoptCurrentSystemSettings() {
        guard started, snapshot.health == .drifted else { return }
        applyCurrentSettings()
    }

    private func installObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main) { [weak self] notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
                Task { @MainActor [weak self] in
                    self?.frontmostBundleID = app?.bundleIdentifier
                    self?.applyCurrentSettings()
                }
            })
        workspaceObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isSleeping = true
                    self.engine.restore(frontmostBundleID: self.frontmostBundleID)
                    self.snapshot = self.engine.snapshot
                }
            })
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            workspaceObservers.append(workspaceCenter.addObserver(
                forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.isSleeping = false
                        self?.applyCurrentSettings()
                    }
                })
        }
    }

    private func startDeviceMonitor() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Mouse,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOHIDDeviceCallback = { context, _, _, _ in
            guard let context else { return }
            let controller = Unmanaged<PointerSettingsController>
                .fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in controller.applyCurrentSettings() }
        }
        IOHIDManagerRegisterDeviceMatchingCallback(manager, callback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, callback, context)
        IOHIDManagerScheduleWithRunLoop(
            manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
                == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(
                manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            return
        }
        hidManager = manager
    }

    private func applyCurrentSettings() {
        guard !isSleeping else { return }
        engine.apply(config: config, frontmostBundleID: frontmostBundleID)
        snapshot = engine.snapshot
    }
}
