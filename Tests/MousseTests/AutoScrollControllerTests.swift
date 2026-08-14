import XCTest
@testable import Mousse

final class AutoScrollControllerTests: XCTestCase {

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
        _ = c.tick(pointer: CGPoint(x: 100, y: 100)) // anchor
        let down = c.tick(pointer: CGPoint(x: 100, y: 140))
        XCTAssertEqual(down.deltaY, -40, accuracy: 1e-9, "pointer down → scroll down")
        let up = c.tick(pointer: CGPoint(x: 100, y: 120))
        XCTAssertEqual(up.deltaY, 20, accuracy: 1e-9, "pointer up → scroll up")
        // horizontal: pointer right → scroll right (positive)
        let right = c.tick(pointer: CGPoint(x: 150, y: 120))
        XCTAssertEqual(right.deltaX, 50, accuracy: 1e-9)
    }

    /// Inactive: never produces scroll.
    func testInactiveNeverScrolls() {
        let c = AutoScrollController()
        XCTAssertEqual(c.tick(pointer: CGPoint(x: 200, y: 200)).deltaY, 0)
        XCTAssertEqual(c.tick(pointer: CGPoint(x: 50, y: 50)).deltaY, 0)
    }

    /// Entering anchors the current position — the pointer position AT the trigger must not
    /// produce a burst.
    func testEnteringAnchorsPosition() {
        let c = AutoScrollController()
        c.toggle()
        // first tick after entering (even with a huge jump) produces nothing
        XCTAssertEqual(c.tick(pointer: CGPoint(x: 0, y: 0)).deltaY, 0)
        // subsequent movement counts
        XCTAssertEqual(c.tick(pointer: CGPoint(x: 0, y: 10)).deltaY, -10, accuracy: 1e-9)
    }

    /// Re-entering re-anchors: a pointer jump across the mode boundary is not scrolled.
    func testReenterAnchorsAgain() {
        let c = AutoScrollController()
        c.toggle()
        _ = c.tick(pointer: CGPoint(x: 100, y: 100))
        _ = c.tick(pointer: CGPoint(x: 100, y: 300)) // scrolls 200
        c.toggle() // exit
        c.toggle() // re-enter at a different position
        XCTAssertEqual(c.tick(pointer: CGPoint(x: 500, y: 900)).deltaY, 0, "re-anchored")
    }

    /// Cancel (sleep/wake, device change) exits the mode.
    func testCancelExits() {
        let c = AutoScrollController()
        c.toggle()
        XCTAssertTrue(c.isActive)
        c.cancel()
        XCTAssertFalse(c.isActive)
        XCTAssertEqual(c.tick(pointer: CGPoint(x: 1, y: 1)).deltaY, 0)
    }
}
