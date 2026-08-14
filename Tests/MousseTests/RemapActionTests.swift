import XCTest
@testable import Mousse

/// Guards the button-action model: every variant must survive Codable round-trips (a mapping that
/// fails to decode would silently vanish from the user's config) and the preset display names that
/// the Settings UI relies on must stay stable.
final class RemapActionTests: XCTestCase {

    private func roundTrip(_ action: RemapAction) throws -> RemapAction {
        let data = try JSONEncoder().encode(action)
        return try JSONDecoder().decode(RemapAction.self, from: data)
    }

    func testKeyStrokeRoundTrip() throws {
        let action = RemapAction.keyStroke(keyCode: 0x09, control: false, option: false,
                                           command: true, shift: true) // ⌘⇧V
        XCTAssertEqual(try roundTrip(action), action)
    }

    func testPresetsRoundTrip() throws {
        for preset in RemapAction.presets {
            XCTAssertEqual(try roundTrip(preset), preset, "preset failed round-trip: \(preset)")
        }
    }

    func testLaunchpadRoundTrip() throws {
        XCTAssertEqual(try roundTrip(.launchpad), .launchpad)
    }

    func testOpenAppRoundTrip() throws {
        let action = RemapAction.openApp(path: "/Applications/Safari.app", displayName: "Safari")
        XCTAssertEqual(try roundTrip(action), action)
    }

    func testOpenAppDisplayName() {
        XCTAssertEqual(RemapAction.openApp(path: "/Applications/Safari.app",
                                           displayName: "Safari").displayName, "Safari")
        XCTAssertEqual(RemapAction.openApp(path: "/Applications/Safari.app",
                                           displayName: "").displayName,
                       Localized.text("action.openApp"))
    }

    func testNavigationRoundTrip() throws {
        XCTAssertEqual(try roundTrip(.navigateBack), .navigateBack)
        XCTAssertEqual(try roundTrip(.navigateForward), .navigateForward)
    }

    func testMediaKeyRoundTrip() throws {
        XCTAssertEqual(try roundTrip(.mediaKey(.playPause)), .mediaKey(.playPause))
    }

    func testPresetDisplayNamesAreNonEmptyAndDistinct() {
        let names = RemapAction.presets.map(\.displayName)
        XCTAssertTrue(names.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(Set(names).count, names.count)
    }

    /// A custom combo renders modifier glyphs in a stable order (⌃⌥⇧⌘).
    func testCustomKeyStrokeDisplayShowsModifiers() {
        let action = RemapAction.keyStroke(keyCode: 0x00, control: true, option: true,
                                           command: true, shift: true)
        let name = action.displayName
        XCTAssertTrue(name.hasPrefix("⌃⌥⇧⌘"), "unexpected modifier order: \(name)")
    }

    func testKeyboardCaptureResultCreatesKeyStroke() {
        let result = EventTapEngine.KeyboardCaptureResult(
            keyCode: 0x09, control: true, option: false, command: true, shift: true)
        XCTAssertEqual(result.action,
                       .keyStroke(keyCode: 0x09, control: true, option: false,
                                  command: true, shift: true))
    }
}
