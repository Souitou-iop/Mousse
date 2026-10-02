import XCTest
@testable import Mousse

final class ScrollControlTests: XCTestCase {
    func testSharedControlVisibilityMatchesEachMode() {
        // wheel speed, zoom, smoothness, acceleration, lines, high-res smoothing
        let expected: [(ScrollMode, [Bool])] = [
            (.native, [false, false, false, false, false, false]),
            (.standard, [true, true, false, false, false, false]),
            (.smooth, [true, true, true, true, false, true]),
            (.smoothStep, [true, true, false, false, true, true]),
        ]
        for (mode, flags) in expected {
            XCTAssertEqual([mode.supportsWheelSpeed, mode.supportsWheelZoom, mode.supportsSmoothness,
                mode.supportsAcceleration, mode.supportsLinesPerNotch, mode.supportsHighResSmoothing], flags)
        }
        XCTAssertEqual(ScrollMode.standard.wheelSpeedNoteKey, "scroll.speedStandardNote")
        XCTAssertEqual(ScrollMode.smoothStep.wheelSpeedNoteKey, "scroll.speedStepNote")
        XCTAssertNil(ScrollMode.native.wheelSpeedNoteKey)
        XCTAssertNil(ScrollMode.smooth.wheelSpeedNoteKey)
    }

    func testCLIHelpExplainsLegacyAndBaseSettingsSemantics() {
        XCTAssertTrue(CLICommand.helpText.contains("writes BOTH axes"))
        XCTAssertTrue(CLICommand.helpText.contains("reads vertical"))
        XCTAssertTrue(CLICommand.helpText.contains("reverseScrollHorizontal"))
        XCTAssertTrue(CLICommand.helpText.contains("native"))
        XCTAssertTrue(CLICommand.helpText.contains("baseScrollSettings"))
    }
}
