import XCTest
@testable import Mousse

final class DeviceProfileTests: XCTestCase {
    func testLegacyGlobalFallbackAndDeviceRoundTrip() throws {
        let legacy = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"reverseScroll":true}"#.utf8))
        XCTAssertTrue(legacy.deviceProfiles.isEmpty)
        XCTAssertTrue(legacy.scrollSettings.reverseScrollHorizontal)
        var config = legacy
        var settings = config.scrollSettings
        settings.scrollSpeed = 3
        settings.zoomSpeed = 6
        settings.scrollMode = .standard
        settings.reverseScrollHorizontal = false
        config.deviceProfiles = [DeviceProfile(id: "046d:c548", name: "Mouse", settings: settings)]
        XCTAssertEqual(try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(config)), config)
        config.scrollSettings = settings
        XCTAssertEqual(config.scrollSettings, settings)
    }

    func testDeviceFieldsAreTolerantAndUseForkRanges() throws {
        let settings = try JSONDecoder().decode(ScrollDeviceSettings.self, from: Data(#"""
{
            "reverseScroll":true,"reverseScrollHorizontal":"bad","scrollMode":"unknown",
            "scrollSmoothness":"bad","scrollSpeed":99,"zoomSpeed":99,"scrollLines":999,
            "scrollAcceleration":"bad","smoothHighRes":true
        }
"""#.utf8))
        XCTAssertTrue(settings.reverseScroll)
        XCTAssertTrue(settings.reverseScrollHorizontal)
        XCTAssertEqual(settings.scrollMode, .smooth)
        XCTAssertEqual(settings.scrollSmoothness, .balanced)
        XCTAssertEqual(settings.scrollSpeed, 3)
        XCTAssertEqual(settings.zoomSpeed, 6)
        XCTAssertEqual(settings.scrollLines, 10)
        XCTAssertTrue(settings.scrollAcceleration)
        XCTAssertTrue(settings.smoothHighRes)
        var broken = ScrollDeviceSettings()
        broken.scrollSpeed = .infinity
        broken.zoomSpeed = .nan
        broken.scrollLines = -1
        broken.clampToUIRanges()
        XCTAssertEqual(broken.scrollSpeed, 0.5)
        XCTAssertEqual(broken.zoomSpeed, 1)
        XCTAssertEqual(broken.scrollLines, 1)
    }

    func testLossyArrayAndImportDuplicateValidation() throws {
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(#"""
{"deviceProfiles":[
            1,{"id":"046d:c548","name":"Mouse","settings":{"scrollSpeed":2.9}},
            {"id":12,"name":"Bad","settings":{}},{"id":"bad","name":"Bad","settings":false}
        ]}
"""#.utf8))
        XCTAssertEqual(config.deviceProfiles.count, 1)
        XCTAssertEqual(config.deviceProfiles[0].settings.scrollSpeed, 2.9)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mousse-device-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("config.json")
        try ConfigTransfer.export(config, to: url)
        XCTAssertEqual(try ConfigTransfer.importConfig(from: url), config)
        var duplicate = config
        duplicate.deviceProfiles.append(config.deviceProfiles[0])
        try ConfigTransfer.export(duplicate, to: url)
        XCTAssertThrowsError(try ConfigTransfer.importConfig(from: url)) {
            XCTAssertEqual($0 as? ConfigTransferError, .duplicateDeviceProfile("046d:c548"))
        }
    }

    func testDeviceFallbackThenAppOverrideAndHardPassthrough() {
        let global = ScrollDeviceSettings()
        var device = global
        device.scrollSpeed = 2.7
        device.zoomSpeed = 5.8
        device.reverseScroll = true
        device.reverseScrollHorizontal = true
        let table = ["mouse": device]
        XCTAssertEqual(EventTapEngine.resolveDeviceScrollSettings(activeKey: nil, profiles: table, global: global), global)
        XCTAssertEqual(EventTapEngine.resolveDeviceScrollSettings(activeKey: "unknown", profiles: table, global: global), global)
        let effective = EventTapEngine.resolveDeviceScrollSettings(activeKey: "mouse", profiles: table, global: global)
        XCTAssertEqual(effective, device)
        let app = ScrollAppProfile(bundleID: "app", mousseScrollEnabled: false,
                                   reverseScroll: false, reverseScrollHorizontal: true)
        let override = EventTapEngine.resolveScrollAppSettings(bundleID: "app", profiles: ["app": app],
            excluded: [], globalReverse: effective.reverseScroll,
            globalReverseHorizontal: effective.reverseScrollHorizontal)
        XCTAssertEqual(override, .init(mousseScrollEnabled: false, reverseScroll: false, reverseScrollHorizontal: true))
        XCTAssertEqual(EventTapEngine.resolveScrollAppSettings(bundleID: "com.apple.Terminal", profiles: [:],
            excluded: [], globalReverse: effective.reverseScroll, globalReverseHorizontal: effective.reverseScrollHorizontal),
            .init(mousseScrollEnabled: false, reverseScroll: false))
        let mirror = EventTapEngine.resolveScrollAppSettings(bundleID: "com.apple.ScreenContinuity", profiles: [:],
            excluded: [], globalReverse: effective.reverseScroll, globalReverseHorizontal: effective.reverseScrollHorizontal)
        XCTAssertFalse(mirror.mousseScrollEnabled)
        XCTAssertTrue(mirror.reverseScroll)
        XCTAssertTrue(mirror.reverseScrollHorizontal)
        XCTAssertEqual(EventTapEngine.resolveScrollAppSettings(bundleID: nil, profiles: [:], excluded: [],
            globalReverse: effective.reverseScroll, globalReverseHorizontal: effective.reverseScrollHorizontal),
            .init(mousseScrollEnabled: true, reverseScroll: true, reverseScrollHorizontal: true))
    }

    func testDiagnosticsReportDeviceBaseWithoutTouchingLiveConfig() {
        var config = AppConfig()
        var device = ScrollDeviceSettings()
        device.scrollSpeed = 2.8
        device.zoomSpeed = 5.9
        config.deviceProfiles = [DeviceProfile(id: "mouse", name: "Mouse", settings: device)]
        let matched = AppCommandDelegate.deviceScrollDiagnostics(config: config, activeKey: "mouse")
        XCTAssertEqual(matched["activeDeviceKey"] as? String, "mouse")
        XCTAssertEqual(matched["matchedDeviceProfileKey"] as? String, "mouse")
        let settings = matched["baseScrollSettings"] as? [String: Any]
        XCTAssertEqual(settings?["scrollSpeed"] as? Double, 2.8)
        XCTAssertEqual(settings?["zoomSpeed"] as? Double, 5.9)
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: matched))
        let fallback = AppCommandDelegate.deviceScrollDiagnostics(config: config, activeKey: nil)
        XCTAssertTrue(fallback["activeDeviceKey"] is NSNull)
        XCTAssertTrue(fallback["matchedDeviceProfileKey"] is NSNull)
        XCTAssertEqual((fallback["baseScrollSettings"] as? [String: Any])?["scrollSpeed"] as? Double, 0.5)
    }

}
