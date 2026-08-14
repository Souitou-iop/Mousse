import XCTest
@testable import Mousse

final class HoldScrollGestureTests: XCTestCase {

    /// Pressing the configured button enters the mode immediately (no hold-duration wait) and
    /// swallows the down/up.
    func testPressActivatesImmediatelyAndReleaseRestores() {
        let gesture = HoldScrollGesture()
        gesture.mappings = [3: .volume]
        var steps: [Int] = []
        gesture.volumeStep = { steps.append($0) }

        XCTAssertTrue(gesture.handleButtonDown(buttonNumber: 3))
        XCTAssertTrue(gesture.isActive)
        _ = gesture.handleScroll(lineDelta: 1)
        XCTAssertEqual(steps, [1])
        XCTAssertTrue(gesture.handleButtonUp(buttonNumber: 3))
        XCTAssertFalse(gesture.isActive)
    }

    /// Wheel input while active converts to the output and is consumed.
    func testScrollConvertsToVolumeAndIsConsumed() {
        let gesture = HoldScrollGesture()
        gesture.mappings = [3: .volume]
        var steps: [Int] = []
        gesture.volumeStep = { steps.append($0) }

        XCTAssertTrue(gesture.handleButtonDown(buttonNumber: 3))
        XCTAssertTrue(gesture.handleScroll(lineDelta: 1))   // up → +1
        XCTAssertTrue(gesture.handleScroll(lineDelta: -1))  // down → −1
        XCTAssertTrue(gesture.handleScroll(lineDelta: -3))  // direction only, not magnitude
        XCTAssertEqual(steps, [1, -1, -1])
    }

    /// Unconfigured buttons are never swallowed: the gesture must not hijack other buttons.
    func testUnconfiguredButtonNotSwallowed() {
        let gesture = HoldScrollGesture()
        gesture.mappings = [3: .volume] // only the middle button is configured
        var steps: [Int] = []
        gesture.volumeStep = { steps.append($0) }

        XCTAssertFalse(gesture.handleButtonDown(buttonNumber: 4), "side button not ours")
        XCTAssertFalse(gesture.handleScroll(lineDelta: 1))
        XCTAssertFalse(gesture.handleButtonUp(buttonNumber: 4))
        XCTAssertEqual(steps, [])

        // after release, another button is still not affected
        XCTAssertTrue(gesture.handleButtonDown(buttonNumber: 3))
        _ = gesture.handleButtonUp(buttonNumber: 3)
        XCTAssertFalse(gesture.handleButtonDown(buttonNumber: 5))
    }

    /// Multiple buttons can be configured independently.
    func testMultipleConfiguredButtons() {
        let gesture = HoldScrollGesture()
        gesture.mappings = [3: .volume, 4: .volume]
        var steps: [Int] = []
        gesture.volumeStep = { steps.append($0) }

        XCTAssertTrue(gesture.handleButtonDown(buttonNumber: 4))
        _ = gesture.handleScroll(lineDelta: 1)
        XCTAssertEqual(steps, [1])
        XCTAssertTrue(gesture.handleButtonUp(buttonNumber: 4))
        _ = gesture.handleScroll(lineDelta: 1) // released → not consumed
        XCTAssertEqual(steps, [1])
    }

    /// Release of a DIFFERENT button than the one holding the mode must not end it.
    func testForeignButtonUpDoesNotEndMode() {
        let gesture = HoldScrollGesture()
        gesture.mappings = [3: .volume, 4: .volume]
        XCTAssertTrue(gesture.handleButtonDown(buttonNumber: 3))
        XCTAssertFalse(gesture.handleButtonUp(buttonNumber: 4), "foreign up must be passed through")
        XCTAssertTrue(gesture.isActive)
        XCTAssertTrue(gesture.handleButtonUp(buttonNumber: 3))
        XCTAssertFalse(gesture.isActive)
    }

    /// Cancel (sleep/wake, device change) ends the mode so a lost button-up can't wedge it.
    func testCancelEndsMode() {
        let gesture = HoldScrollGesture()
        gesture.mappings = [3: .volume]
        XCTAssertTrue(gesture.handleButtonDown(buttonNumber: 3))
        gesture.cancel()
        XCTAssertFalse(gesture.isActive)
        XCTAssertFalse(gesture.handleScroll(lineDelta: 1))
        XCTAssertFalse(gesture.handleButtonUp(buttonNumber: 3), "after cancel the up is not ours")
    }
}
