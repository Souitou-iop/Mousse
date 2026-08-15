import XCTest
@testable import Mousse

final class CompiledButtonMappingsTests: XCTestCase {
    func testCompilesClickDoubleClickAndHoldActions() {
        let compiled = CompiledButtonMappings([
            ButtonMapping(buttonNumber: 4, action: .navigateBack),
            ButtonMapping(buttonNumber: 4, trigger: .doubleClick, action: .navigateForward),
            ButtonMapping(buttonNumber: 4, trigger: .hold, action: .spotlight),
        ])
        XCTAssertEqual(compiled.actionsByButton[4], .init(
            click: .navigateBack,
            doubleClick: .navigateForward,
            hold: .spotlight))
    }

    func testPlaceholderMappingsAreFiltered() {
        let compiled = CompiledButtonMappings([
            ButtonMapping(buttonNumber: 4, trigger: .click, action: .none),
        ])
        XCTAssertNil(compiled.actionsByButton[4])
    }

    func testCompilesHoldScrollSeparatelyFromHoldAction() {
        let compiled = CompiledButtonMappings([
            ButtonMapping(buttonNumber: 5, trigger: .hold, action: .scrollOutput(.volume)),
        ])
        XCTAssertNil(compiled.actionsByButton[5])
        XCTAssertEqual(compiled.holdScrollByButton[5], .volume)
    }
}
