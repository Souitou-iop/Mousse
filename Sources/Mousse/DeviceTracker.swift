import Foundation
import Combine
import os

struct HIDDeviceInfo: Identifiable, Equatable, Sendable {
    let key: String
    let name: String
    var id: String { key }
    static func key(vendorID: Int, productID: Int) -> String {
        String(format: "%04x:%04x", vendorID, productID)
    }
}

protocol DeviceTrackingSession: AnyObject {
    func start()
    func stop()
}

/// Control methods and published state are main-thread-only; active-key callbacks/readers use lock.
/// HID and CGEvent delivery are unordered: the first event after a mouse switch can use the old key.
final class DeviceTracker: ObservableObject {
    static let shared = DeviceTracker()
    @Published private(set) var connected: [HIDDeviceInfo] = []
    @Published private(set) var inputMonitoringGranted = false
    private let lock = OSAllocatedUnfairLock()
    private var activeKey: String?
    private var identity: UUID?
    private var session: DeviceTrackingSession?
    private var shutDown = false
    private var enabled = false
    private var hasProfiles = false
    private var tabOpen = false
    private var retryTimer: Timer?
    private let permission: () -> Bool
    private let sessionFactory: (DeviceTracker, UUID) -> DeviceTrackingSession
    private let automaticallyRetry: Bool

    init(permission: @escaping () -> Bool = { InputMonitoringPermission.isTrusted },
         automaticallyRetry: Bool = true,
         sessionFactory: @escaping (DeviceTracker, UUID) -> DeviceTrackingSession = {
             DeviceTrackerSession(tracker: $0, identity: $1)
         }) {
        self.permission = permission
        self.automaticallyRetry = automaticallyRetry
        self.sessionFactory = sessionFactory
    }

    func configure(enabled: Bool, hasProfiles: Bool) {
        self.enabled = enabled
        self.hasProfiles = hasProfiles
        update()
    }

    func setTabOpen(_ value: Bool) {
        guard tabOpen != value else { return }
        tabOpen = value
        update()
    }

    var isNeeded: Bool { !shutDown && ((enabled && hasProfiles) || tabOpen) }
    var currentSessionIdentity: UUID? {
        lock.lock(); defer { lock.unlock() }
        return identity
    }
    func activeDeviceKey() -> String? {
        lock.lock(); defer { lock.unlock() }
        return activeKey
    }
    private func accepts(_ id: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return identity == id
    }

    private func update() {
        guard isNeeded else { stopSession(); cancelRetry(); return }
        let granted = permission()
        if inputMonitoringGranted != granted { inputMonitoringGranted = granted }
        guard granted else { stopSession(); scheduleRetry(); return }
        guard session == nil else { return }
        cancelRetry()
        let id = UUID()
        let newSession = sessionFactory(self, id)
        lock.lock(); identity = id; lock.unlock()
        session = newSession
        newSession.start()
    }

    private func stopSession() {
        // Invalidate identity BEFORE asking the old thread to exit: no callback can resurrect state.
        lock.lock(); identity = nil; activeKey = nil; lock.unlock()
        let old = session
        session = nil
        old?.stop()
        if !connected.isEmpty { connected = [] }
    }

    private func cancelRetry() { retryTimer?.invalidate(); retryTimer = nil }
    private func scheduleRetry() {
        guard isNeeded, automaticallyRetry, retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.retryIfNeeded()
        }
    }
    func retryIfNeeded() { update() }
    func shutdown() {
        shutDown = true
        enabled = false; hasProfiles = false; tabOpen = false
        stopSession(); cancelRetry()
    }

    func sessionOpenFailed(from id: UUID) {
        guard accepts(id) else { return }
        stopSession()
        scheduleRetry()
    }
    func publish(_ list: [HIDDeviceInfo], from id: UUID) {
        guard accepts(id), connected != list else { return }
        connected = list
    }
    func setActiveKey(_ key: String?, from id: UUID) {
        lock.lock(); defer { lock.unlock() }
        guard identity == id else { return }
        activeKey = key
    }
    func deviceGone(_ key: String, from id: UUID) {
        lock.lock(); defer { lock.unlock() }
        guard identity == id else { return }
        if activeKey == key { activeKey = nil }
    }
}
