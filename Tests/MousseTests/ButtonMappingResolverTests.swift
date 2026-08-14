import XCTest
@testable import Mousse

/// Guards per-app button mapping precedence: an app override only replaces the buttons it
/// configures, every other button falls back to the global mapping.
final class ButtonMappingResolverTests: XCTestCase {

    private func makeConfig(global: [ButtonMapping] = [],
                            perApp: [AppMappings] = []) -> AppConfig {
        var config = AppConfig()
        config.mappings = global
        config.perAppMappings = perApp
        return config
    }

    func testNoPerAppUsesGlobalOnly() {
        let config = makeConfig(global: [
            ButtonMapping(buttonNumber: 4, action: .navigateBack),
            ButtonMapping(buttonNumber: 5, action: .navigateForward),
        ])
        let resolver = ButtonMappingResolver(config: config)
        XCTAssertFalse(resolver.hasPerAppMappings)
        let resolved = resolver.resolved(for: "com.apple.Safari")
        XCTAssertNotNil(resolved.actionsByButton[4])
        XCTAssertNotNil(resolved.actionsByButton[5])
    }

    func testAppOverrideOnlyReplacesConfiguredButtons() {
        let config = makeConfig(
            global: [
                ButtonMapping(buttonNumber: 4, action: .navigateBack),
                ButtonMapping(buttonNumber: 5, action: .navigateForward),
            ],
            perApp: [
                AppMappings(bundleID: "com.apple.Safari",
                            mappings: [ButtonMapping(buttonNumber: 4, action: .spaceLeft)]),
            ])
        let resolver = ButtonMappingResolver(config: config)
        XCTAssertTrue(resolver.hasPerAppMappings)

        let safari = resolver.resolved(for: "com.apple.Safari")
        XCTAssertEqual(safari.actionsByButton[4], .init(click: .spaceLeft))
        XCTAssertEqual(safari.actionsByButton[5], .init(click: .navigateForward))

        let other = resolver.resolved(for: "com.google.Chrome")
        XCTAssertEqual(other.actionsByButton[4], .init(click: .navigateBack))
        XCTAssertEqual(other.actionsByButton[5], .init(click: .navigateForward))
    }

    func testNilBundleIDFallsBackToGlobal() {
        let config = makeConfig(
            global: [ButtonMapping(buttonNumber: 4, action: .navigateBack)],
            perApp: [AppMappings(bundleID: "com.apple.Safari",
                                 mappings: [ButtonMapping(buttonNumber: 4, action: .spaceLeft)])])
        let resolver = ButtonMappingResolver(config: config)
        XCTAssertEqual(resolver.resolved(for: nil).actionsByButton[4],
                       .init(click: .navigateBack))
    }

    func testPlaceholderMappingsAreFiltered() {
        let config = makeConfig(global: [
            ButtonMapping(buttonNumber: 4, trigger: .click, action: .none),
        ])
        let resolver = ButtonMappingResolver(config: config)
        XCTAssertNil(resolver.resolved(for: nil).actionsByButton[4])
    }

    func testHoldScrollIsResolvedPerApp() {
        let config = makeConfig(
            global: [ButtonMapping(buttonNumber: 5, trigger: .hold, action: .scrollOutput(.volume))],
            perApp: [AppMappings(bundleID: "com.apple.Safari",
                                 mappings: [ButtonMapping(buttonNumber: 4, trigger: .hold,
                                                          action: .scrollOutput(.volume))])])
        let resolver = ButtonMappingResolver(config: config)
        let safari = resolver.resolved(for: "com.apple.Safari")
        XCTAssertEqual(safari.holdScrollByButton[4], .volume)
        XCTAssertEqual(safari.holdScrollByButton[5], .volume)
        let other = resolver.resolved(for: "com.google.Chrome")
        XCTAssertNil(other.holdScrollByButton[4])
        XCTAssertEqual(other.holdScrollByButton[5], .volume)
    }
}
