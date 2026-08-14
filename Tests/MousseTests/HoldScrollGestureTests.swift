import XCTest
@testable import Mousse

final class HoldScrollGestureTests: XCTestCase {

    /// Press enters the mode immediately (no hold-duration wait) and swallows the down/up.
    func testPressActivatesImmediatelyAndReleaseRestores() {
        let gesture = HoldScrollGesture()
        gesture.output = .volume
        var steps: [Int] = []
        gesture.volumeStep = { steps.append($0) }

        XCTAssertTrue(gesture.handleButtonDown(buttonNumber: 4))
        XCTAssertTrue(gesture.isActive)
        _ = gesture.handleScroll(lineDelta: 1)
        XCTAssertEqual(steps, [1])
        XCTAssertTrue(gesture.handleButtonUp(buttonNumber: 4))
        XCTAssertFalse(gesture.isActive)
    }

    /// Wheel input while active converts to the output and is consumed.
    func testScrollConvertsToVolumeAndIsConsumed() {
        let gesture = HoldScrollGesture()
        gesture.output = .volume
        var steps: [Int] = []
        gesture.volumeStep = { steps.append($0) }

        XCTAssertTrue(gesture.handleButtonDown(buttonNumber: 4))
        XCTAssertTrue(gesture.handleScroll(lineDelta: 1))   // up → +1
        XCTAssertTrue(gesture.handleScroll(lineDelta: -1))  // down → −1
        XCTAssertTrue(gesture.handleScroll(lineDelta: -3))  // direction only, not magnitude
        XCTAssertEqual(steps, [1, -1, -1])
    }

    /// Not configured (no output) or not active: never consumes anything.
    func testInactiveNeverConsumes() {
        let gesture = HoldScrollGesture()
        var steps: [Int] = []
        gesture.volumeStep = { steps.append($0) }

        XCTAssertFalse(gesture.handleButtonDown(buttonNumber: 4), "no output → not ours")
        XCTAssertFalse(gesture.handleScroll(lineDelta: 1))
        XCTAssertFalse(gesture.handleButtonUp(buttonNumber: 4))

        gesture.output = .volume
        XCTAssertTrue(gesture.handleButtonDown(buttonNumber: 4))
        _ = gesture.handleButtonUp(buttonNumber: 4)
        XCTAssertFalse(gesture.handleScroll(lineDelta: 1), "released → not consumed")
        XCTAssertEqual(steps, [])
    }

    /// Cancel (sleep/wake, device change) ends the mode so a lost button-up can't wedge it.
    func testCancelEndsMode() {
        let gesture = HoldScrollGesture()
        gesture.output = .volume
        XCTAssertTrue(gesture.handleButtonDown(buttonNumber: 4))
        gesture.cancel()
        XCTAssertFalse(gesture.isActive)
        XCTAssertFalse(gesture.handleScroll(lineDelta: 1))
        XCTAssertFalse(gesture.handleButtonUp(buttonNumber: 4), "after cancel the up is not ours")
    }
}
