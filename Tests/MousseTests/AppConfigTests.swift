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
        XCTAssertEqual(decoded.showAutoScrollHUD, true)
        XCTAssertEqual(decoded.autoScrollClickDelay, 0.20, accuracy: 1e-9)
        XCTAssertEqual(decoded.reverseScroll, false)
        XCTAssertEqual(decoded.mappings.count, AppConfig.defaultMappings.count)
        XCTAssertFalse(decoded.pointerControlEnabled)
        XCTAssertTrue(decoded.pointerAccelerationEnabled)
        XCTAssertEqual(decoded.pointerSpeedMultiplier, 1.0, accuracy: 1e-9)
        XCTAssertTrue(decoded.pointerAppProfiles.isEmpty)
    }

    func testEveryLanguageRoundTrips() throws {
        for language in AppLanguage.allCases {
            var config = AppConfig()
            config.language = language
            XCTAssertEqual(try roundTrip(config).language, language, "\(language) failed round-trip")
            XCTAssertFalse(language.label.isEmpty)
        }
    }

    func testEveryLanguageLabelResolvesInsteadOfReturningTheKey() {
        for language in AppLanguage.allCases {
            let key = language == .system ? "general.language.system" : ""
            let label = language.label
            if !key.isEmpty {
                XCTAssertNotEqual(label, key, "\(language) fell back to the raw localization key")
            }
            XCTAssertFalse(label.isEmpty, "\(language) label is empty")
        }
    }

    func testSystemLanguageFollowsChinesePreferredLocale() {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
        guard preferred.hasPrefix("zh-hans") || preferred.hasPrefix("zh-cn") else { return }
        Localized.language = .system
        XCTAssertEqual(Localized.text("general.enable"), "启用 Mousse",
                       "system language should resolve the zh-hans.lproj bundle")
        XCTAssertEqual(Localized.text("general.language.system"), "跟随系统")
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
        config.showAutoScrollHUD = false
        config.autoScrollClickDelay = 0.35
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
        XCTAssertEqual(decoded.showAutoScrollHUD, false)
        XCTAssertEqual(decoded.autoScrollClickDelay, 0.35, accuracy: 1e-9)
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
        XCTAssertEqual(decoded.scrollSpeed, 3.0, accuracy: 1e-9)
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
        XCTAssertEqual(low.autoScrollSpeed, 0.25, accuracy: 1e-9)
        let high = try JSONDecoder().decode(AppConfig.self,
            from: #"{"autoScrollSpeed":9.0}"#.data(using: .utf8)!)
        XCTAssertEqual(high.autoScrollSpeed, 8.0, accuracy: 1e-9)
    }

    func testAutoScrollSpeedStepIncludesRequestedValuesAndRoundTrips() throws {
        for value in [0.25, 0.30, 0.95, 1.0, 2.0, 8.0] {
            XCTAssertTrue(AutoScrollSpeedSetting.range.contains(value))
            let stepIndex = (value - AutoScrollSpeedSetting.range.lowerBound)
                / AutoScrollSpeedSetting.step
            XCTAssertEqual(stepIndex, stepIndex.rounded(), accuracy: 1e-9)

            var config = AppConfig()
            config.autoScrollSpeed = value
            XCTAssertEqual(try roundTrip(config).autoScrollSpeed, value, accuracy: 1e-9)
        }
    }

    func testAutoScrollClickDelayDefaultsClampsAndRoundTrips() throws {
        let legacy = try JSONDecoder().decode(
            AppConfig.self, from: #"{}"#.data(using: .utf8)!)
        XCTAssertEqual(legacy.autoScrollClickDelay, 0.20, accuracy: 1e-9)

        let low = try JSONDecoder().decode(
            AppConfig.self, from: #"{"autoScrollClickDelay":0.01}"#.data(using: .utf8)!)
        XCTAssertEqual(low.autoScrollClickDelay, 0.05, accuracy: 1e-9)
        let high = try JSONDecoder().decode(
            AppConfig.self, from: #"{"autoScrollClickDelay":0.8}"#.data(using: .utf8)!)
        XCTAssertEqual(high.autoScrollClickDelay, 0.50, accuracy: 1e-9)

        for value in [0.05, 0.20, 0.50] {
            var config = AppConfig()
            config.autoScrollClickDelay = value
            XCTAssertEqual(try roundTrip(config).autoScrollClickDelay, value, accuracy: 1e-9)
        }
    }

    func testPointerSettingsRoundTripAndLegacyDefaults() throws {
        let legacy = try JSONDecoder().decode(
            AppConfig.self, from: #"{}"#.data(using: .utf8)!)
        XCTAssertFalse(legacy.pointerControlEnabled)
        XCTAssertTrue(legacy.pointerAccelerationEnabled)
        XCTAssertEqual(legacy.pointerSpeedMultiplier, 1.0, accuracy: 1e-9)
        XCTAssertTrue(legacy.pointerAppProfiles.isEmpty)

        var config = AppConfig()
        config.pointerControlEnabled = true
        config.pointerAccelerationEnabled = false
        config.pointerSpeedMultiplier = 1.75
        config.pointerAppProfiles = [
            PointerAppProfile(
                bundleID: "com.apple.Safari", acceleration: .enabled,
                speedMultiplier: 0.75),
            PointerAppProfile(bundleID: "com.apple.Terminal", acceleration: .disabled),
        ]

        let decoded = try roundTrip(config)
        XCTAssertEqual(decoded.pointerControlEnabled, true)
        XCTAssertEqual(decoded.pointerAccelerationEnabled, false)
        XCTAssertEqual(decoded.pointerSpeedMultiplier, 1.75, accuracy: 1e-9)
        XCTAssertEqual(decoded.pointerAppProfiles, config.pointerAppProfiles)
    }

    func testPointerSpeedValuesClampDuringDecode() throws {
        let low = try JSONDecoder().decode(
            AppConfig.self,
            from: #"{"pointerSpeedMultiplier":0.1,"pointerAppProfiles":[{"bundleID":"low","speedMultiplier":0.1}]}"#
                .data(using: .utf8)!)
        XCTAssertEqual(low.pointerSpeedMultiplier, 0.25, accuracy: 1e-9)
        XCTAssertEqual(low.pointerAppProfiles[0].speedMultiplier!, 0.25, accuracy: 1e-9)

        let high = try JSONDecoder().decode(
            AppConfig.self,
            from: #"{"pointerSpeedMultiplier":8,"pointerAppProfiles":[{"bundleID":"high","speedMultiplier":8}]}"#
                .data(using: .utf8)!)
        XCTAssertEqual(high.pointerSpeedMultiplier, 4.0, accuracy: 1e-9)
        XCTAssertEqual(high.pointerAppProfiles[0].speedMultiplier!, 4.0, accuracy: 1e-9)
    }

    func testPointerProfileToleratesUnknownOverrideAndInvalidSpeed() throws {
        let json = #"{"pointerAppProfiles":[{"bundleID":"com.apple.Safari","acceleration":"future","speedMultiplier":"fast"}]}"#
        let decoded = try JSONDecoder().decode(AppConfig.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(decoded.pointerAppProfiles.count, 1)
        XCTAssertEqual(decoded.pointerAppProfiles[0].acceleration, .inherit)
        XCTAssertNil(decoded.pointerAppProfiles[0].speedMultiplier)
    }

    func testConfigImportRejectsDuplicatePointerProfilesAndIgnoresLegacyButtonProfiles() throws {
        let duplicate = #"{"pointerAppProfiles":[{"bundleID":"com.apple.Safari"},{"bundleID":"com.apple.Safari"}]}"#
        let duplicateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try duplicate.data(using: .utf8)!.write(to: duplicateURL)
        defer { try? FileManager.default.removeItem(at: duplicateURL) }
        XCTAssertThrowsError(try ConfigTransfer.importConfig(from: duplicateURL)) { error in
            XCTAssertEqual(error as? ConfigTransferError,
                           .duplicateAppProfile("com.apple.Safari"))
        }

        let independent = #"{"perAppMappings":[{"bundleID":"com.apple.Safari"}],"pointerAppProfiles":[{"bundleID":"com.apple.Safari"}]}"#
        let independentURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try independent.data(using: .utf8)!.write(to: independentURL)
        defer { try? FileManager.default.removeItem(at: independentURL) }
        let imported = try ConfigTransfer.importConfig(from: independentURL)
        let reencoded = try JSONEncoder().encode(imported)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: reencoded) as? [String: Any])
        XCTAssertNil(object["perAppMappings"])
    }

    /// Auto-scroll base speed clamps to its UI range on decode.
    func testAutoScrollBaseSpeedClamps() throws {
        let low = try JSONDecoder().decode(AppConfig.self,
            from: #"{"autoScrollBaseSpeed":-50}"#.data(using: .utf8)!)
        XCTAssertEqual(low.autoScrollBaseSpeed, 0, accuracy: 1e-9)
        let high = try JSONDecoder().decode(AppConfig.self,
            from: #"{"autoScrollBaseSpeed":5000}"#.data(using: .utf8)!)
        XCTAssertEqual(high.autoScrollBaseSpeed, 1000, accuracy: 1e-9)
    }

    /// Zoom speed clamps to its UI range on decode (a hand-edited value must not extrapolate).
    func testZoomSpeedClamps() throws {
        let low = try JSONDecoder().decode(AppConfig.self,
            from: #"{"zoomSpeed":0.1}"#.data(using: .utf8)!)
        XCTAssertEqual(low.zoomSpeed, 0.2, accuracy: 1e-9)
        let high = try JSONDecoder().decode(AppConfig.self,
            from: #"{"zoomSpeed":9.0}"#.data(using: .utf8)!)
        XCTAssertEqual(high.zoomSpeed, 6.0, accuracy: 1e-9)
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

    // MARK: - Config export/import

    func testConfigTransferRoundTrip() throws {
        var config = AppConfig()
        config.enabled = false
        config.scrollMode = .smoothStep
        config.configuredButtons = [4, 5, 6]
        config.mappings = [ButtonMapping(buttonNumber: 6, trigger: .doubleClick, action: .spotlight)]
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }

        try ConfigTransfer.export(config, to: url)
        XCTAssertEqual(try ConfigTransfer.importConfig(from: url), config)
    }

    func testConfigImportRejectsMalformedFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not json".utf8).write(to: url)

        XCTAssertThrowsError(try ConfigTransfer.importConfig(from: url))
    }

    func testConfigImportRejectsNonObjectTopLevel() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("[]".utf8).write(to: url)

        XCTAssertThrowsError(try ConfigTransfer.importConfig(from: url)) { error in
            XCTAssertEqual(error as? ConfigTransferError, .invalidTopLevel)
        }
    }

}
