import XCTest
@testable import Mousse

private final class FakePointerHIDBackend: PointerHIDBackend {
    var isAvailable = true
    var ids: [UInt64] = []
    var values: [UInt64: [PointerHIDProperty: Int64]] = [:]
    var failingWrites: Set<UInt64> = []
    var writes: [(UInt64, PointerHIDProperty, Int64)] = []

    func deviceIDs() -> [UInt64] { ids }

    func read(_ property: PointerHIDProperty, deviceID: UInt64) -> Int64? {
        values[deviceID]?[property]
    }

    func write(_ value: Int64, property: PointerHIDProperty, deviceID: UInt64) -> Bool {
        writes.append((deviceID, property, value))
        guard !failingWrites.contains(deviceID) else { return false }
        values[deviceID, default: [:]][property] = value
        return true
    }
}

final class PointerSettingsControllerTests: XCTestCase {
    private let oneX = Int64(400 * 65_536)

    private func backend(ids: [UInt64] = [1]) -> FakePointerHIDBackend {
        let backend = FakePointerHIDBackend()
        backend.ids = ids
        for id in ids {
            backend.values[id] = [
                .linearAcceleration: 0,
                .pointerResolution: oneX,
            ]
        }
        return backend
    }

    func testResolverUsesGlobalThenPerAppOverrides() {
        var config = AppConfig()
        config.pointerControlEnabled = true
        config.pointerAccelerationEnabled = true
        config.pointerSpeedMultiplier = 1.25
        config.pointerAppProfiles = [
            PointerAppProfile(
                bundleID: "com.apple.Safari", acceleration: .disabled,
                speedMultiplier: 2),
            PointerAppProfile(bundleID: "com.apple.Terminal", acceleration: .inherit),
        ]

        XCTAssertEqual(
            PointerSettingsResolver.resolve(config: config, frontmostBundleID: nil),
            PointerSettingsTarget(
                accelerationEnabled: true, speedMultiplier: 1.25,
                matchedProfileBundleID: nil))
        XCTAssertEqual(
            PointerSettingsResolver.resolve(
                config: config, frontmostBundleID: "com.apple.Safari"),
            PointerSettingsTarget(
                accelerationEnabled: false, speedMultiplier: 2,
                matchedProfileBundleID: "com.apple.Safari"))
        XCTAssertEqual(
            PointerSettingsResolver.resolve(
                config: config, frontmostBundleID: "com.apple.Terminal"),
            PointerSettingsTarget(
                accelerationEnabled: true, speedMultiplier: 1.25,
                matchedProfileBundleID: "com.apple.Terminal"))
    }

    func testResolverDisablesManagementWithEitherMasterSwitch() {
        var config = AppConfig()
        config.pointerControlEnabled = false
        XCTAssertNil(PointerSettingsResolver.resolve(config: config, frontmostBundleID: nil))
        config.pointerControlEnabled = true
        config.enabled = false
        XCTAssertNil(PointerSettingsResolver.resolve(config: config, frontmostBundleID: nil))
    }

    func testResolutionUsesRelativeMultiplierAndClamps() {
        XCTAssertEqual(
            PointerSettingsEngine.adjustedResolution(
                baselineRawValue: oneX, multiplier: 2),
            Int64(200 * 65_536))
        XCTAssertEqual(
            PointerSettingsEngine.adjustedResolution(
                baselineRawValue: Int64(20 * 65_536), multiplier: 4),
            Int64(10 * 65_536))
        XCTAssertEqual(
            PointerSettingsEngine.adjustedResolution(
                baselineRawValue: Int64(1_000 * 65_536), multiplier: 0.25),
            Int64(1_995 * 65_536))
    }

    func testApplyWritesOnlyChangedValuesAndIsIdempotent() {
        let backend = backend()
        let engine = PointerSettingsEngine(backend: backend)
        var config = AppConfig()
        config.pointerControlEnabled = true
        config.pointerAccelerationEnabled = false
        config.pointerSpeedMultiplier = 2

        engine.apply(config: config, frontmostBundleID: nil)
        XCTAssertEqual(backend.values[1]?[.linearAcceleration], 1)
        XCTAssertEqual(backend.values[1]?[.pointerResolution], Int64(200 * 65_536))
        XCTAssertEqual(engine.snapshot.appliedDeviceCount, 1)
        XCTAssertEqual(engine.snapshot.actualAccelerationEnabled, false)
        XCTAssertEqual(engine.snapshot.actualSpeedMultiplier, 2)
        let firstWriteCount = backend.writes.count

        engine.apply(config: config, frontmostBundleID: nil)
        XCTAssertEqual(backend.writes.count, firstWriteCount)
    }

    func testDisablingManagementRestoresOriginalValues() {
        let backend = backend()
        let engine = PointerSettingsEngine(backend: backend)
        var config = AppConfig()
        config.pointerControlEnabled = true
        config.pointerAccelerationEnabled = false
        config.pointerSpeedMultiplier = 2
        engine.apply(config: config, frontmostBundleID: "app")

        config.pointerControlEnabled = false
        engine.apply(config: config, frontmostBundleID: "app")

        XCTAssertEqual(backend.values[1]?[.linearAcceleration], 0)
        XCTAssertEqual(backend.values[1]?[.pointerResolution], oneX)
        XCTAssertEqual(engine.snapshot.health, .inactive)
        XCTAssertFalse(engine.snapshot.managementEnabled)
    }

    func testDeviceReconnectCapturesFreshBaseline() {
        let backend = backend()
        let engine = PointerSettingsEngine(backend: backend)
        var config = AppConfig()
        config.pointerControlEnabled = true
        config.pointerSpeedMultiplier = 2
        engine.apply(config: config, frontmostBundleID: nil)

        backend.ids = []
        engine.apply(config: config, frontmostBundleID: nil)
        backend.ids = [2]
        backend.values[2] = [
            .linearAcceleration: 0,
            .pointerResolution: Int64(800 * 65_536),
        ]
        engine.apply(config: config, frontmostBundleID: nil)

        XCTAssertEqual(backend.values[2]?[.pointerResolution], Int64(400 * 65_536))
        XCTAssertEqual(engine.snapshot.appliedDeviceCount, 1)
    }

    func testOneDeviceFailureDoesNotBlockAnother() {
        let backend = backend(ids: [1, 2])
        backend.failingWrites = [2]
        let engine = PointerSettingsEngine(backend: backend)
        var config = AppConfig()
        config.pointerControlEnabled = true
        config.pointerAccelerationEnabled = false

        engine.apply(config: config, frontmostBundleID: nil)

        XCTAssertEqual(backend.values[1]?[.linearAcceleration], 1)
        XCTAssertEqual(backend.values[2]?[.linearAcceleration], 0)
        XCTAssertEqual(engine.snapshot.appliedDeviceCount, 1)
        XCTAssertEqual(engine.snapshot.health, .failed)
        XCTAssertEqual(engine.snapshot.failureReason, .writeFailed)
    }

    func testDiagnosticsReportsDriftWithoutReapplying() {
        let backend = backend()
        let engine = PointerSettingsEngine(backend: backend)
        var config = AppConfig()
        config.pointerControlEnabled = true
        config.pointerAccelerationEnabled = false
        engine.apply(config: config, frontmostBundleID: nil)
        let writeCount = backend.writes.count

        backend.values[1]?[.linearAcceleration] = 0
        XCTAssertEqual(engine.refreshDiagnostics().health, .drifted)
        XCTAssertEqual(engine.snapshot.failureReason, .externalChange)
        XCTAssertEqual(engine.snapshot.actualAccelerationEnabled, true)
        XCTAssertEqual(backend.writes.count, writeCount)
    }

    func testExternalResolutionChangeBecomesRestoreBaselineWithoutPolling() {
        let backend = backend()
        let engine = PointerSettingsEngine(backend: backend)
        var config = AppConfig()
        config.pointerControlEnabled = true
        config.pointerAccelerationEnabled = false
        config.pointerSpeedMultiplier = 2
        engine.apply(config: config, frontmostBundleID: nil)

        let externalResolution = Int64(300 * 65_536)
        backend.values[1]?[.pointerResolution] = externalResolution
        config.pointerControlEnabled = false
        engine.apply(config: config, frontmostBundleID: nil)

        XCTAssertEqual(backend.values[1]?[.pointerResolution], externalResolution)
        XCTAssertEqual(backend.values[1]?[.linearAcceleration], 0)
    }

    func testExternalChangeRebasesOnlyChangedProperty() {
        let backend = backend()
        let engine = PointerSettingsEngine(backend: backend)
        var config = AppConfig()
        config.pointerControlEnabled = true
        config.pointerAccelerationEnabled = false
        config.pointerSpeedMultiplier = 2
        engine.apply(config: config, frontmostBundleID: nil)

        let externalResolution = Int64(300 * 65_536)
        backend.values[1]?[.pointerResolution] = externalResolution
        XCTAssertEqual(engine.refreshDiagnostics().health, .drifted)

        config.pointerControlEnabled = false
        engine.apply(config: config, frontmostBundleID: nil)
        XCTAssertEqual(backend.values[1]?[.pointerResolution], externalResolution)
        XCTAssertEqual(backend.values[1]?[.linearAcceleration], 0)
    }

    func testReapplyUsesExternallyUpdatedResolutionAsNewBaseline() {
        let backend = backend()
        let engine = PointerSettingsEngine(backend: backend)
        var config = AppConfig()
        config.pointerControlEnabled = true
        config.pointerSpeedMultiplier = 2
        engine.apply(config: config, frontmostBundleID: nil)

        backend.values[1]?[.pointerResolution] = Int64(300 * 65_536)
        XCTAssertEqual(engine.refreshDiagnostics().health, .drifted)
        engine.apply(config: config, frontmostBundleID: nil)

        XCTAssertEqual(backend.values[1]?[.pointerResolution], Int64(150 * 65_536))
        config.pointerControlEnabled = false
        engine.apply(config: config, frontmostBundleID: nil)
        XCTAssertEqual(backend.values[1]?[.pointerResolution], Int64(300 * 65_536))
    }

    func testUnavailableBackendDoesNotWrite() {
        let backend = backend()
        backend.isAvailable = false
        let engine = PointerSettingsEngine(backend: backend)
        var config = AppConfig()
        config.pointerControlEnabled = true

        engine.apply(config: config, frontmostBundleID: nil)

        XCTAssertEqual(engine.snapshot.health, .unavailable)
        XCTAssertEqual(engine.snapshot.failureReason, .serviceUnavailable)
        XCTAssertTrue(backend.writes.isEmpty)
    }

    func testRestoreFailureIsReported() {
        let backend = backend()
        let engine = PointerSettingsEngine(backend: backend)
        var config = AppConfig()
        config.pointerControlEnabled = true
        config.pointerAccelerationEnabled = false
        engine.apply(config: config, frontmostBundleID: nil)

        backend.failingWrites = [1]
        config.pointerControlEnabled = false
        engine.apply(config: config, frontmostBundleID: nil)

        XCTAssertEqual(engine.snapshot.health, .failed)
        XCTAssertEqual(engine.snapshot.failureReason, .restoreFailed)
    }
}
