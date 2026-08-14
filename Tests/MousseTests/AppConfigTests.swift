import XCTest
@testable import Mousse

/// Guards the persisted-config contract: round-trips, tolerant decoding (a missing key OR an
/// invalid value must fall back to that field's default, never throw — throwing would wipe the
/// user's saved settings), and the legacy `smoothScroll` bool → `ScrollMode` bridge.
final class AppConfigTests: XCTestCase {

    private func roundTrip(_ config: AppConfig) throws -> AppConfig {
        let data = try JSONEncoder().encode(config)
        return try JSONDecoder().decode(AppConfig.self, from: data)
    }

    func testDefaultsRoundTrip() throws {
        let decoded = try roundTrip(AppConfig())
        XCTAssertEqual(decoded.enabled, true)
        XCTAssertEqual(decoded.scrollMode, .smooth)
        XCTAssertEqual(decoded.scrollSpeed, 0.5, accuracy: 1e-9)
        XCTAssertEqual(decoded.scrollLines, 3)
        XCTAssertEqual(decoded.scrollAcceleration, true)
        XCTAssertEqual(decoded.smoothHighRes, false)
        XCTAssertEqual(decoded.reverseScroll, false)
        XCTAssertEqual(decoded.mappings.count, AppConfig.defaultMappings.count)
    }

    func testNonDefaultValuesPersist() throws {
        var config = AppConfig()
        config.enabled = false
        config.language = .simplifiedChinese
        config.reverseScroll = true
        config.scrollMode = .smoothStep
        config.scrollSpeed = 1.3
        config.scrollLines = 7
        config.scrollAcceleration = false
        config.smoothHighRes = true
        config.doubleClickInterval = 0.42
        config.holdDuration = 0.75
        config.spaceDragButton = 4
        config.spaceDragThreshold = 250
        config.spaceDragReverse = true
        config.excludedBundleIDs = ["info.filesmanager.Files", "com.example.other"]
        config.verticalToHorizontalBundleIDs = ["info.filesmanager.Files"]
        config.scrollSmoothness = .floaty
        config.configuredButtons = [3, 6]
        config.mappings = [ButtonMapping(buttonNumber: 6, trigger: .doubleClick,
                                         action: .missionControl)]

        let decoded = try roundTrip(config)
        XCTAssertEqual(decoded.enabled, false)
        XCTAssertEqual(decoded.language, .simplifiedChinese)
        XCTAssertEqual(decoded.reverseScroll, true)
        XCTAssertEqual(decoded.scrollMode, .smoothStep)
        XCTAssertEqual(decoded.scrollSpeed, 1.3, accuracy: 1e-9)
        XCTAssertEqual(decoded.scrollLines, 7)
        XCTAssertEqual(decoded.scrollAcceleration, false)
        XCTAssertEqual(decoded.smoothHighRes, true)
        XCTAssertEqual(decoded.doubleClickInterval, 0.42, accuracy: 1e-9)
        XCTAssertEqual(decoded.holdDuration, 0.75, accuracy: 1e-9)
        XCTAssertEqual(decoded.spaceDragButton, 4)
        XCTAssertEqual(decoded.spaceDragThreshold, 250, accuracy: 1e-9)
        XCTAssertEqual(decoded.spaceDragReverse, true)
        XCTAssertEqual(decoded.excludedBundleIDs, ["info.filesmanager.Files", "com.example.other"])
        XCTAssertEqual(decoded.verticalToHorizontalBundleIDs, ["info.filesmanager.Files"])
        XCTAssertEqual(decoded.scrollSmoothness, .floaty)
        XCTAssertEqual(decoded.configuredButtons, [3, 6])
        XCTAssertEqual(decoded.mappings, config.mappings)
    }

    /// An old config saved before a setting existed must decode with that setting at its default,
    /// not throw and reset everything.
    func testMissingKeysFallBackToDefaults() throws {
        let partial = #"{"enabled":false,"reverseScroll":true}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppConfig.self, from: partial)
        XCTAssertEqual(decoded.enabled, false)
        XCTAssertEqual(decoded.language, .system)
        XCTAssertEqual(decoded.reverseScroll, true)
        // Everything absent falls back to defaults.
        XCTAssertEqual(decoded.scrollMode, .smooth)
        XCTAssertEqual(decoded.scrollLines, 3)
        XCTAssertEqual(decoded.smoothHighRes, false)
        XCTAssertEqual(decoded.excludedBundleIDs, [])
        XCTAssertEqual(decoded.verticalToHorizontalBundleIDs, [])
        XCTAssertEqual(decoded.scrollSmoothness, .balanced)
        XCTAssertEqual(decoded.mappings.count, AppConfig.defaultMappings.count)
    }

    func testEmptyObjectDecodesToDefaults() throws {
        let decoded = try JSONDecoder().decode(AppConfig.self, from: #"{}"#.data(using: .utf8)!)
        XCTAssertEqual(decoded.scrollMode, AppConfig().scrollMode)
        XCTAssertEqual(decoded.scrollSpeed, AppConfig().scrollSpeed, accuracy: 1e-9)
    }

    /// Legacy bridge: configs predating `scrollMode` stored a `smoothScroll` bool.
    func testLegacySmoothScrollTrueMapsToSmooth() throws {
        let legacy = #"{"smoothScroll":true}"#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(AppConfig.self, from: legacy).scrollMode, .smooth)
    }

    func testLegacySmoothScrollFalseMapsToStandard() throws {
        let legacy = #"{"smoothScroll":false}"#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(AppConfig.self, from: legacy).scrollMode, .standard)
    }

    /// A present `scrollMode` wins over the legacy bool when both appear.
    func testScrollModeWinsOverLegacyBool() throws {
        let both = #"{"scrollMode":"smoothStep","smoothScroll":false}"#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(AppConfig.self, from: both).scrollMode, .smoothStep)
    }

    // MARK: - Present-but-invalid values (config from a newer app version, or hand-edited)

    /// An unknown enum case resets THAT field only — every other saved setting must survive.
    func testUnknownEnumValueFallsBackWithoutWipingRest() throws {
        let json = #"{"scrollMode":"turbo","enabled":false,"scrollLines":7}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppConfig.self, from: json)
        XCTAssertEqual(decoded.scrollMode, .smooth) // unknown case → default
        XCTAssertEqual(decoded.enabled, false)      // neighbors survive
        XCTAssertEqual(decoded.scrollLines, 7)
    }

    func testUnknownLanguageFallsBackWithoutWipingRest() throws {
        let json = #"{"language":"klingon","enabled":false}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppConfig.self, from: json)
        XCTAssertEqual(decoded.language, .system)
        XCTAssertEqual(decoded.enabled, false)
    }

    func testWrongTypeValueFallsBackWithoutWipingRest() throws {
        let json = #"{"scrollSpeed":"fast","reverseScroll":true}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppConfig.self, from: json)
        XCTAssertEqual(decoded.scrollSpeed, 0.5, accuracy: 1e-9)
        XCTAssertEqual(decoded.reverseScroll, true)
    }

    /// One broken mapping is dropped; intact ones survive (previously it wiped the whole config).
    func testBrokenMappingElementIsDroppedNotFatal() throws {
        let good = String(data: try JSONEncoder().encode(ButtonMapping(buttonNumber: 4, action: .spaceLeft)),
                          encoding: .utf8)!
        let json = #"{"scrollLines":7,"mappings":[\#(good),{"buttonNumber":5,"action":{"warpDrive":{}}}]}"#
        let decoded = try JSONDecoder().decode(AppConfig.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(decoded.mappings.count, 1)
        XCTAssertEqual(decoded.mappings[0].buttonNumber, 4)
        XCTAssertEqual(decoded.mappings[0].trigger, .click)
        XCTAssertEqual(decoded.mappings[0].action, .spaceLeft)
        XCTAssertEqual(decoded.scrollLines, 7)
    }

    /// A mapping missing its `id` (hand-edited/older file) keeps the mapping under a fresh id.
    func testMappingWithoutIdIsKept() throws {
        let json = #"{"mappings":[{"buttonNumber":6,"action":{"launchpad":{}}}]}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppConfig.self, from: json)
        XCTAssertEqual(decoded.mappings.count, 1)
        XCTAssertEqual(decoded.mappings[0].buttonNumber, 6)
        XCTAssertEqual(decoded.mappings[0].trigger, .click)
        XCTAssertEqual(decoded.mappings[0].action, .launchpad)
    }

    func testLegacyConfigDerivesConfiguredButtonsFromMappings() throws {
        let mappings = [
            ButtonMapping(buttonNumber: 6, action: .launchpad),
            ButtonMapping(buttonNumber: 4, action: .spaceLeft),
        ]
        let encodedMappings = try JSONEncoder().encode(mappings)
        let mappingObjects = try JSONSerialization.jsonObject(with: encodedMappings)
        let json = try JSONSerialization.data(withJSONObject: ["mappings": mappingObjects])
        let decoded = try JSONDecoder().decode(AppConfig.self, from: json)
        XCTAssertEqual(decoded.configuredButtons, [4, 6])
    }

    func testEmptyConfiguredButtonPersists() throws {
        var config = AppConfig()
        config.configuredButtons = [4, 7]
        config.mappings.removeAll { $0.buttonNumber == 7 }
        XCTAssertEqual(try roundTrip(config).configuredButtons, [4, 5, 7])
    }

    func testConfiguredButtonsAreNormalizedAndIncludeMappedButtons() throws {
        let json = #"{"configuredButtons":[7,4,7,2,-1],"mappings":[{"buttonNumber":6,"action":{"launchpad":{}}}]}"#
            .data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppConfig.self, from: json)
        XCTAssertEqual(decoded.configuredButtons, [4, 6, 7])
    }

    func testExplicitlyEmptyMappingsKeepEmptyButtonGroups() throws {
        let json = #"{"configuredButtons":[8],"mappings":[]}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppConfig.self, from: json)
        XCTAssertEqual(decoded.configuredButtons, [8])
        XCTAssertTrue(decoded.mappings.isEmpty)
    }

    func testInvalidMappingsFieldFallsBackWithoutLosingDefaults() throws {
        let json = #"{"configuredButtons":[8],"mappings":"broken"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppConfig.self, from: json)
        XCTAssertEqual(decoded.configuredButtons, [4, 5, 8])
        XCTAssertEqual(decoded.mappings, AppConfig.defaultMappings)
    }

    func testUnknownMappingTriggerFallsBackToClick() throws {
        let json = #"{"mappings":[{"buttonNumber":6,"trigger":"tripleClick","action":{"launchpad":{}}}]}"#
            .data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppConfig.self, from: json)
        XCTAssertEqual(decoded.mappings.count, 1)
        XCTAssertEqual(decoded.mappings[0].trigger, .click)
        XCTAssertEqual(decoded.mappings[0].action, .launchpad)
    }

    func testTriggerTimingIsClampedToSupportedRanges() throws {
        let json = #"{"doubleClickInterval":5,"holdDuration":0.01}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppConfig.self, from: json)
        XCTAssertEqual(decoded.doubleClickInterval, 0.50, accuracy: 1e-9)
        XCTAssertEqual(decoded.holdDuration, 0.10, accuracy: 1e-9)
    }

    func testTriggerTimingAcceptsNewBoundaries() throws {
        let json = #"{"doubleClickInterval":0.1,"holdDuration":0.8}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppConfig.self, from: json)
        XCTAssertEqual(decoded.doubleClickInterval, 0.10, accuracy: 1e-9)
        XCTAssertEqual(decoded.holdDuration, 0.80, accuracy: 1e-9)
    }

    /// A structurally wrong file (top level not an object) yields defaults instead of throwing.
    func testNonObjectTopLevelDecodesToDefaults() throws {
        let decoded = try JSONDecoder().decode(AppConfig.self, from: #"[]"#.data(using: .utf8)!)
        XCTAssertEqual(decoded.enabled, AppConfig().enabled)
        XCTAssertEqual(decoded.mappings.count, AppConfig.defaultMappings.count)
    }

    func testOutOfRangeValuesAreClamped() throws {
        let json = #"{"scrollSpeed":99,"scrollLines":-2,"spaceDragThreshold":5}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppConfig.self, from: json)
        XCTAssertEqual(decoded.scrollSpeed, 1.5, accuracy: 1e-9)
        XCTAssertEqual(decoded.scrollLines, 1)
        XCTAssertEqual(decoded.spaceDragThreshold, 100, accuracy: 1e-9)
    }

    func testInRangeValuesSurviveClamp() throws {
        let json = #"{"scrollSpeed":0.05,"scrollLines":10,"spaceDragThreshold":400}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppConfig.self, from: json)
        XCTAssertEqual(decoded.scrollSpeed, 0.05, accuracy: 1e-9)
        XCTAssertEqual(decoded.scrollLines, 10)
        XCTAssertEqual(decoded.spaceDragThreshold, 400, accuracy: 1e-9)
    }

    /// Auto-scroll speed clamps to its UI range on decode.
    func testAutoScrollSpeedClamps() throws {
        let low = try JSONDecoder().decode(AppConfig.self,
            from: #"{"autoScrollSpeed":0.1}"#.data(using: .utf8)!)
        XCTAssertEqual(low.autoScrollSpeed, 0.5, accuracy: 1e-9)
        let high = try JSONDecoder().decode(AppConfig.self,
            from: #"{"autoScrollSpeed":9.0}"#.data(using: .utf8)!)
        XCTAssertEqual(high.autoScrollSpeed, 4.0, accuracy: 1e-9)
    }

    /// Zoom speed clamps to its UI range on decode (a hand-edited value must not extrapolate).
    func testZoomSpeedClamps() throws {
        let low = try JSONDecoder().decode(AppConfig.self,
            from: #"{"zoomSpeed":0.1}"#.data(using: .utf8)!)
        XCTAssertEqual(low.zoomSpeed, 0.5, accuracy: 1e-9)
        let high = try JSONDecoder().decode(AppConfig.self,
            from: #"{"zoomSpeed":9.0}"#.data(using: .utf8)!)
        XCTAssertEqual(high.zoomSpeed, 3.0, accuracy: 1e-9)
        let mid = try JSONDecoder().decode(AppConfig.self,
            from: #"{"zoomSpeed":1.7}"#.data(using: .utf8)!)
        XCTAssertEqual(mid.zoomSpeed, 1.7, accuracy: 1e-9)
    }

    func testScrollExclusionMatchHasPriority() {
        let excluded: Set<String> = ["com.example.Editor"]
        XCTAssertTrue(EventTapEngine.isScrollExcluded("com.example.Editor", from: excluded))
        XCTAssertFalse(EventTapEngine.isScrollExcluded("com.example.Browser", from: excluded))
        XCTAssertFalse(EventTapEngine.isScrollExcluded(nil, from: excluded))
    }
}
