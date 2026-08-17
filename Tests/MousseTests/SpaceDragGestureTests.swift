import XCTest
@testable import Mousse

final class SpaceDragGestureTests: XCTestCase {
    func testReleaseInsideDeadzoneIsClick() {
        let gesture = SpaceDragGesture()
        gesture.button = 4
        gesture.followFinger = false

        XCTAssertTrue(gesture.handleButtonDown(4))
        XCTAssertTrue(gesture.handleDrag(deltaX: 5, deltaY: 4))
        XCTAssertFalse(gesture.hasDragged)
        XCTAssertEqual(gesture.handleButtonUp(4).wasClick, true)
    }

    func testCrossingDeadzoneBecomesDragWithoutTriggeringClick() {
        let gesture = SpaceDragGesture()
        gesture.button = 4
        gesture.followFinger = false

        XCTAssertTrue(gesture.handleButtonDown(4))
        XCTAssertTrue(gesture.handleDrag(deltaX: 11, deltaY: 0))
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

    // MARK: - Pointer freeze (MMF "lock pointer during drag")

    /// A plain click (never crossing the deadzone) must not freeze the pointer.
    func testClickDoesNotFreezePointer() {
        let gesture = SpaceDragGesture()
        gesture.button = 4
        var freezes = 0
        var unfreezes = 0
        gesture.freezePointer = { freezes += 1 }
        gesture.unfreezePointer = { unfreezes += 1 }

        XCTAssertTrue(gesture.handleButtonDown(4))
        _ = gesture.handleDrag(deltaX: 3, deltaY: 2) // inside deadzone
        _ = gesture.handleButtonUp(4)
        // Release always calls unfreeze — it's idempotent (PointerFreeze guards on `isFrozen`),
        // so a plain click must simply never have frozen anything.
        XCTAssertEqual(freezes, 0)
    }

    /// Crossing the deadzone freezes once; releasing unfreezes once.
    func testDragFreezesPointerAndReleaseUnfreezes() {
        let gesture = SpaceDragGesture()
        gesture.button = 4
        gesture.followFinger = false
        var freezes = 0
        var unfreezes = 0
        gesture.freezePointer = { freezes += 1 }
        gesture.unfreezePointer = { unfreezes += 1 }

        XCTAssertTrue(gesture.handleButtonDown(4))
        _ = gesture.handleDrag(deltaX: 11, deltaY: 0) // crosses deadzone
        XCTAssertEqual(freezes, 1, "must freeze exactly once at drag start")
        _ = gesture.handleDrag(deltaX: 3, deltaY: 0)
        _ = gesture.handleDrag(deltaX: 2, deltaY: 0)
        XCTAssertEqual(freezes, 1, "must not re-freeze mid-drag")
        _ = gesture.handleButtonUp(4)
        XCTAssertEqual(unfreezes, 1)
    }

    /// Cancel (sleep/wake, device change) must also release the pointer.
    func testCancelUnfreezesPointer() {
        let gesture = SpaceDragGesture()
        gesture.button = 4
        gesture.followFinger = false
        var freezes = 0
        var unfreezes = 0
        gesture.freezePointer = { freezes += 1 }
        gesture.unfreezePointer = { unfreezes += 1 }

        XCTAssertTrue(gesture.handleButtonDown(4))
        _ = gesture.handleDrag(deltaX: 11, deltaY: 0)
        XCTAssertEqual(freezes, 1)
        gesture.cancel()
        XCTAssertEqual(unfreezes, 1)
    }

    /// With the option off, no freeze happens at all.
    func testLockPointerOffNeverFreezes() {
        let gesture = SpaceDragGesture()
        gesture.button = 4
        gesture.followFinger = false
        gesture.lockPointer = false
        var freezes = 0
        var unfreezes = 0
        gesture.freezePointer = { freezes += 1 }
        gesture.unfreezePointer = { unfreezes += 1 }

        XCTAssertTrue(gesture.handleButtonDown(4))
        _ = gesture.handleDrag(deltaX: 12, deltaY: 0)
        _ = gesture.handleButtonUp(4)
        XCTAssertEqual(freezes, 0)
    }
}
