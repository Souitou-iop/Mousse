import XCTest
import Combine
@testable import Mousse

final class DeviceTrackerTests: XCTestCase {
    private final class Session: DeviceTrackingSession {
        var starts = 0
        var stops = 0
        func start() { starts += 1 }
        func stop() { stops += 1 }
    }

    @MainActor
    func testDemandAndRepeatedStartStopNeverStartRealHID() {
        var sessions: [Session] = []
        let tracker = DeviceTracker(permission: { true }, automaticallyRetry: false) { _, _ in
            let session = Session(); sessions.append(session); return session
        }
        defer { tracker.shutdown() }
        tracker.configure(enabled: false, hasProfiles: true)
        XCTAssertTrue(sessions.isEmpty)
        tracker.setTabOpen(true) // Visible UI discovers mice even with processing disabled.
        XCTAssertEqual(sessions.count, 1)
        tracker.setTabOpen(false) // Closing / hiding UI stops disabled background tracking.
        XCTAssertEqual(sessions[0].stops, 1)
        tracker.configure(enabled: true, hasProfiles: false)
        XCTAssertEqual(sessions.count, 1)
        tracker.setTabOpen(true)
        tracker.configure(enabled: true, hasProfiles: false)
        tracker.setTabOpen(true)
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[1].starts, 1)
        let id = tracker.currentSessionIdentity!
        tracker.setActiveKey("0001:0002", from: id)
        tracker.publish([HIDDeviceInfo(key: "0001:0002", name: "Mouse")], from: id)
        tracker.setTabOpen(false)
        tracker.setTabOpen(false)
        XCTAssertNil(tracker.activeDeviceKey())
        XCTAssertTrue(tracker.connected.isEmpty)
        XCTAssertEqual(sessions[1].stops, 1)
        tracker.configure(enabled: true, hasProfiles: true)
        XCTAssertEqual(sessions.count, 3)
        tracker.setTabOpen(true)
        tracker.setTabOpen(false) // Background tracking remains needed by the profile.
        XCTAssertEqual(sessions[2].stops, 0)
        tracker.configure(enabled: false, hasProfiles: true)
        XCTAssertEqual(sessions[2].stops, 1)
        tracker.retryIfNeeded()
        XCTAssertEqual(sessions.count, 3)
        tracker.shutdown()
        tracker.setTabOpen(true) // A queued UI notification cannot restart tracking during quit.
        tracker.retryIfNeeded()
        XCTAssertEqual(sessions.count, 3)
    }

    @MainActor
    func testPermissionAndOpenFailureRetryRefreshOnlyChangedState() {
        var granted = false
        var sessions: [Session] = []
        let tracker = DeviceTracker(permission: { granted }, automaticallyRetry: false) { _, _ in
            let session = Session(); sessions.append(session); return session
        }
        defer { tracker.shutdown() }
        var permissionPublications = 0
        let observer = tracker.$inputMonitoringGranted.dropFirst().sink { _ in permissionPublications += 1 }
        defer { observer.cancel() }
        tracker.configure(enabled: true, hasProfiles: true)
        tracker.retryIfNeeded()
        XCTAssertTrue(sessions.isEmpty)
        XCTAssertEqual(permissionPublications, 0)
        granted = true
        tracker.retryIfNeeded()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(permissionPublications, 1)
        tracker.retryIfNeeded()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(permissionPublications, 1)
        let old = tracker.currentSessionIdentity!
        tracker.sessionOpenFailed(from: old)
        XCTAssertEqual(sessions[0].stops, 1)
        XCTAssertNil(tracker.currentSessionIdentity)
        tracker.retryIfNeeded()
        XCTAssertEqual(sessions.count, 2)
        XCTAssertNotEqual(old, tracker.currentSessionIdentity)
    }

    @MainActor
    func testAllStaleSessionCallbacksAreRejected() {
        let tracker = DeviceTracker(permission: { true }, automaticallyRetry: false) { _, _ in Session() }
        defer { tracker.shutdown() }
        tracker.configure(enabled: true, hasProfiles: true)
        let old = tracker.currentSessionIdentity!
        tracker.configure(enabled: false, hasProfiles: true)
        tracker.configure(enabled: true, hasProfiles: true)
        let current = tracker.currentSessionIdentity!
        let mouse = HIDDeviceInfo(key: "046d:c548", name: "Mouse")
        tracker.setActiveKey(mouse.key, from: current)
        tracker.publish([mouse], from: current)
        var connectedPublications = 0
        let observer = tracker.$connected.dropFirst().sink { _ in connectedPublications += 1 }
        defer { observer.cancel() }
        tracker.publish([mouse], from: current)
        tracker.publish([], from: old)
        tracker.setActiveKey("stale", from: old)
        tracker.deviceGone(mouse.key, from: old)
        tracker.sessionOpenFailed(from: old)
        XCTAssertEqual(connectedPublications, 0)
        XCTAssertEqual(tracker.connected, [mouse])
        XCTAssertEqual(tracker.activeDeviceKey(), mouse.key)
        XCTAssertEqual(tracker.currentSessionIdentity, current)
        tracker.deviceGone(mouse.key, from: current)
        XCTAssertNil(tracker.activeDeviceKey())
        tracker.setActiveKey(mouse.key, from: current)
        tracker.shutdown()
        tracker.setActiveKey(mouse.key, from: current)
        XCTAssertNil(tracker.activeDeviceKey())
    }

    func testModelKeyAndLastInterfaceRemoval() {
        XCTAssertEqual(HIDDeviceInfo.key(vendorID: 0x46d, productID: 0xc548), "046d:c548")
        let mouse = HIDDeviceInfo(key: "046d:c548", name: "Mouse")
        var registry = HIDDeviceRegistry()
        registry.add(mouse, interface: 1)
        registry.add(mouse, interface: 2)
        XCTAssertEqual(registry.connected, [mouse])
        XCTAssertNil(registry.remove(interface: 1))
        XCTAssertEqual(registry.connected, [mouse])
        XCTAssertEqual(registry.remove(interface: 2), mouse.key)
        XCTAssertTrue(registry.connected.isEmpty)
        XCTAssertNil(registry.remove(interface: 2))
    }

    func testUIVisibilityDemandIncludesWindowLifecycle() {
        XCTAssertTrue(SettingsWindowConfiguration.devicesTabIsVisible(selected: true, windowVisible: true,
            miniaturized: false, occlusionVisible: true, appHidden: false, closing: false))
        let cases: [(Bool, Bool, Bool, Bool, Bool, Bool)] = [
            (false, true, false, true, false, false), // Another tab.
            (true, false, false, true, false, false), // orderOut / hidden window.
            (true, true, true, true, false, false), // Minimized.
            (true, true, false, false, false, false), // Occluded.
            (true, true, false, true, true, false), // App hidden.
            (true, true, false, true, false, true), // willClose before isVisible changes.
        ]
        for c in cases {
            XCTAssertFalse(SettingsWindowConfiguration.devicesTabIsVisible(selected: c.0, windowVisible: c.1,
                miniaturized: c.2, occlusionVisible: c.3, appHidden: c.4, closing: c.5))
        }
    }
}
