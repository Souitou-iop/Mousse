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

    // MARK: - Horizontal cooldown reset per drag

    /// A drag that already switched Spaces arms the horizontal cooldown; the NEXT button-down must
    /// drop it so a rapid follow-up flick isn't swallowed by the first drag's leftover cooldown.
    /// `lastHSwitch = 0` on button-down is exactly what makes the follow-up qualify again.
    func testNewDragResetsHorizontalCooldown() {
        let gesture = SpaceDragGesture()
        gesture.button = 4
        gesture.followFinger = false
        gesture.threshold = 100

        func crossDeadzone() {
            _ = gesture.handleDrag(deltaX: 60, deltaY: 0)   // exceeds deadzone, locks horizontal axis
        }

        // First drag: two threshold crossings fire two Spaced switches, the second arming
        // `lastHSwitch` to "now" — a moment we cannot advance past inside the process.
        XCTAssertTrue(gesture.handleButtonDown(4))
        crossDeadzone()
        _ = gesture.handleDrag(deltaX: 110, deltaY: 0)  // >= threshold → switch #1
        _ = gesture.handleDrag(deltaX: 110, deltaY: 0)  // >= threshold → switch #2 (arms cooldown)
        _ = gesture.handleButtonUp(4)

        // Second drag begins immediately. Its motion must not be discarded on the cooldown branch:
        // it has to reach the threshold and fire on its own, which only happens if button-down
        // reset `lastHSwitch`.
        XCTAssertTrue(gesture.handleButtonDown(4))
        crossDeadzone()
        XCTAssertTrue(gesture.handleDrag(deltaX: 110, deltaY: 0),
                      "the follow-up flick must be tracked, not swallowed by the stale cooldown")
        XCTAssertTrue(gesture.hasDragged)
        _ = gesture.handleButtonUp(4)
    }

    // MARK: - Vertical trigger decision (no real windows or mouse)

    /// Overlay state undetectable (pre-macOS 26): keep the legacy unconditional toggle — both
    /// directions report a live action so the caller keeps arming its cooldown.
    func testVerticalUndetectableKeepsLegacyToggle() {
        for up in [true, false] {
            let gesture = makeGesture(overlay: nil)
            XCTAssertTrue(gesture.triggerVertical(up: up),
                          "undetectable overlay must keep the legacy toggle (up=\(up))")
        }
    }

    /// Overlay closed: either direction opens the matching overlay and remembers the opener.
    func testVerticalWhenClosedOpensAndRemembersOpener() {
        let gesture = makeGesture(overlay: false)
        XCTAssertTrue(gesture.triggerVertical(up: true))
        XCTAssertEqual(gesture.verticalOpenerForTesting, .missionControl)
    }

    /// Overlay open, Mission Control was the opener: DOWN closes it (natural reverse), UP is a no-op.
    func testVerticalOpenMissionControlOnlyClosesDownward() {
        let gesture = makeGesture(overlay: false)
        XCTAssertTrue(gesture.triggerVertical(up: true)) // opens Mission Control
        gesture.overlayProbe = { true }
        XCTAssertFalse(gesture.triggerVertical(up: true), "dragging further up must not re-toggle")
        XCTAssertEqual(gesture.verticalOpenerForTesting, .missionControl, "declined drag keeps the opener")
        XCTAssertTrue(gesture.triggerVertical(up: false), "down is the natural close for Mission Control")
        XCTAssertNil(gesture.verticalOpenerForTesting, "a successful close clears the opener")
    }

    /// Overlay open, App Exposé was the opener: UP closes it, DOWN is a no-op.
    func testVerticalOpenAppExposeOnlyClosesUpward() {
        let gesture = makeGesture(overlay: false)
        XCTAssertTrue(gesture.triggerVertical(up: false)) // opens App Exposé
        gesture.overlayProbe = { true }
        XCTAssertFalse(gesture.triggerVertical(up: false), "dragging further down must not re-toggle")
        XCTAssertEqual(gesture.verticalOpenerForTesting, .appExpose)
        XCTAssertTrue(gesture.triggerVertical(up: true), "up is the natural close for App Exposé")
        XCTAssertNil(gesture.verticalOpenerForTesting)
    }

    /// Overlay open but the opener is unknown (opened by keyboard/trackpad): assume the drag
    /// direction closes, matching the upstream fallback.
    func testVerticalOpenWithUnknownOpenerUsesDragDirection() {
        let gesture = makeGesture(overlay: true)
        XCTAssertTrue(gesture.triggerVertical(up: true))
        XCTAssertNil(gesture.verticalOpenerForTesting)
    }

    /// Probe stub: every test picks the overlay state `triggerVertical` sees without touching
    /// WindowServer, and records the action it would fire instead of posting synthesized events.
    private func makeGesture(overlay: Bool?) -> SpaceDragGesture {
        let gesture = SpaceDragGesture()
        gesture.button = 4
        gesture.followFinger = false
        gesture.overlayProbe = { overlay }
        gesture.verticalActionProbe = { _ in }
        return gesture
    }
}
