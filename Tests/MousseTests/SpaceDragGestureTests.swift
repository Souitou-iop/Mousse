import XCTest
@testable import Mousse

final class SpaceDragGestureTests: XCTestCase {
    func testReleaseInsideDeadzoneIsClick() {
        let gesture = SpaceDragGesture()
        gesture.button = 4
        gesture.followFinger = false

        XCTAssertTrue(gesture.handleButtonDown(4))
        XCTAssertTrue(gesture.handleDrag(deltaX: 3, deltaY: 2))
        XCTAssertFalse(gesture.hasDragged)
        XCTAssertEqual(gesture.handleButtonUp(4).wasClick, true)
    }

    func testCrossingDeadzoneBecomesDragWithoutTriggeringClick() {
        let gesture = SpaceDragGesture()
        gesture.button = 4
        gesture.followFinger = false

        XCTAssertTrue(gesture.handleButtonDown(4))
        XCTAssertTrue(gesture.handleDrag(deltaX: 7, deltaY: 0))
        XCTAssertTrue(gesture.hasDragged)
        XCTAssertEqual(gesture.handleButtonUp(4).wasClick, false)
    }

    func testCancelAbandonsPendingPress() {
        let gesture = SpaceDragGesture()
        gesture.button = 4

        XCTAssertTrue(gesture.handleButtonDown(4))
        gesture.cancel()
        XCTAssertFalse(gesture.isActive)
        XCTAssertFalse(gesture.handleButtonUp(4).consumed)
    }
}
