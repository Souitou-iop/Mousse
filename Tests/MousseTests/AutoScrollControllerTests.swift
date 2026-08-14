import XCTest
@testable import Mousse

final class AutoScrollControllerTests: XCTestCase {

    private let bounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    private func tick(_ c: AutoScrollController, _ x: CGFloat, _ y: CGFloat, at now: Double = 10.0)
        -> (deltaX: Double, deltaY: Double) {
        c.tick(pointer: CGPoint(x: x, y: y), now: now, screenBounds: bounds)
    }

    /// Toggling enters the mode; toggling again exits it.
    func testToggleEntersAndExits() {
        let c = AutoScrollController()
        XCTAssertFalse(c.isActive)
        c.toggle()
        XCTAssertTrue(c.isActive)
        c.toggle()
        XCTAssertFalse(c.isActive)
    }

    /// Moving the pointer down scrolls the page down (negative wheel delta); up scrolls up.
    func testPointerMovementDrivesScrollDirection() {
        let c = AutoScrollController()
        c.toggle()
        _ = tick(c, 100, 100) // anchor
        let down = tick(c, 100, 140)
        XCTAssertEqual(down.deltaY, -40, accuracy: 1e-9, "pointer down → scroll down")
        let up = tick(c, 100, 120)
        XCTAssertEqual(up.deltaY, 20, accuracy: 1e-9, "pointer up → scroll up")
        let right = tick(c, 150, 120)
        XCTAssertEqual(right.deltaX, 50, accuracy: 1e-9, "pointer right → scroll right")
    }

    /// Inactive: never produces scroll.
    func testInactiveNeverScrolls() {
        let c = AutoScrollController()
        XCTAssertEqual(tick(c, 200, 200).deltaY, 0)
        XCTAssertEqual(tick(c, 50, 50).deltaY, 0)
    }

    /// Entering anchors the current position — the pointer position AT the trigger must not
    /// produce a burst.
    func testEnteringAnchorsPosition() {
        let c = AutoScrollController()
        c.toggle()
        XCTAssertEqual(tick(c, 100, 100).deltaY, 0) // first tick after entering: anchor only
        XCTAssertEqual(tick(c, 100, 110).deltaY, -10, accuracy: 1e-9)
    }

    /// Re-entering re-anchors: a pointer jump across the mode boundary is not scrolled.
    func testReenterAnchorsAgain() {
        let c = AutoScrollController()
        c.toggle()
        _ = tick(c, 100, 100)
        _ = tick(c, 100, 300) // scrolls 200
        c.toggle() // exit
        c.toggle() // re-enter at a different position
        XCTAssertEqual(tick(c, 500, 900).deltaY, 0, "re-anchored")
    }

    /// Cancel (sleep/wake, device change) exits the mode.
    func testCancelExits() {
        let c = AutoScrollController()
        c.toggle()
        XCTAssertTrue(c.isActive)
        c.cancel()
        XCTAssertFalse(c.isActive)
        XCTAssertEqual(tick(c, 1, 1).deltaY, 0)
    }

    // MARK: - Edge continuation (unlimited scrolling)

    /// Hitting the bottom edge continues scrolling DOWN at the movement speed it had before.
    func testBottomEdgeContinuesScrollingDown() {
        let c = AutoScrollController()
        c.toggle()
        _ = tick(c, 960, 500, at: 10.0)
        // move down at 300 px/s for one tick (dt = 1/30)
        _ = tick(c, 960, 510, at: 10.0 + 1.0 / 30.0)   // speed becomes 300 px/s
        // now inside the bottom edge band: continues down at 300 px/s
        let cont = tick(c, 960, bounds.maxY - 1, at: 10.0 + 2.0 / 30.0)
        XCTAssertEqual(cont.deltaY, -300.0 / 30.0, accuracy: 1e-6, "edge continues downward scroll")
    }

    /// Hitting the top edge continues scrolling UP.
    func testTopEdgeContinuesScrollingUp() {
        let c = AutoScrollController()
        c.toggle()
        _ = tick(c, 960, 900, at: 10.0)
        _ = tick(c, 960, 890, at: 10.0 + 1.0 / 30.0)   // moving up at 300 px/s
        let cont = tick(c, 960, bounds.minY + 1, at: 10.0 + 2.0 / 30.0)
        XCTAssertEqual(cont.deltaY, 300.0 / 30.0, accuracy: 1e-6, "edge continues upward scroll")
    }

    /// Left/right edges continue horizontally.
    func testSideEdgesContinueHorizontally() {
        let c = AutoScrollController()
        c.toggle()
        _ = tick(c, 960, 540, at: 10.0)
        _ = tick(c, 970, 540, at: 10.0 + 1.0 / 30.0)   // moving right at 300 px/s
        let cont = tick(c, bounds.maxX - 1, 540, at: 10.0 + 2.0 / 30.0)
        XCTAssertEqual(cont.deltaX, 300.0 / 30.0, accuracy: 1e-6, "right edge scrolls right")
    }

    /// Pointer resting in the edge band with no prior movement: nothing to continue — no scroll.
    func testEdgeWithoutPriorSpeedDoesNotScroll() {
        let c = AutoScrollController()
        c.toggle()
        _ = tick(c, 960, bounds.maxY - 1, at: 10.0) // anchor already inside the band, no movement
        let cont = tick(c, 960, bounds.maxY - 1, at: 10.0 + 1.0 / 30.0)
        XCTAssertEqual(cont.deltaY, 0, "no prior speed → no edge scroll")
    }

    /// Leaving the edge band returns to normal pointer-driven scrolling.
    func testLeavingEdgeResumesPointerDriven() {
        let c = AutoScrollController()
        c.toggle()
        _ = tick(c, 960, 500, at: 10.0)
        _ = tick(c, 960, 520, at: 10.0 + 1.0 / 30.0)   // speed 600 px/s down
        _ = tick(c, 960, bounds.maxY - 1, at: 10.0 + 2.0 / 30.0) // in the band → continues
        let back = tick(c, 960, 700, at: 10.0 + 3.0 / 30.0)      // left the band, moved up 379
        XCTAssertEqual(back.deltaY, (700 - (bounds.maxY - 1)) * -1, accuracy: 1e-6,
                       "resumes delta-driven scrolling")
    }
}
