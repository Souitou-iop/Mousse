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

    /// Cancel (sleep/wake, device change) exits the mode.
    func testCancelExits() {
        let c = AutoScrollController()
        c.toggle()
        XCTAssertTrue(c.isActive)
        c.cancel()
        XCTAssertFalse(c.isActive)
    }

    // MARK: - Virtual displacement → scroll deltas

    /// Pointer right → scroll right (positive deltaX); pointer down → scroll down (negative
    /// deltaY, wheel convention).
    func testScrollDeltaDirection() {
        let anchor = CGPoint(x: 100, y: 100)
        let right = AutoScrollController.scrollDelta(from: anchor, to: CGPoint(x: 140, y: 100))
        XCTAssertEqual(right.deltaX, 40, accuracy: 1e-9)
        XCTAssertEqual(right.deltaY, 0, accuracy: 1e-9)

        let down = AutoScrollController.scrollDelta(from: anchor, to: CGPoint(x: 100, y: 140))
        XCTAssertEqual(down.deltaY, -40, accuracy: 1e-9, "pointer down → scroll down")

        let up = AutoScrollController.scrollDelta(from: anchor, to: CGPoint(x: 100, y: 60))
        XCTAssertEqual(up.deltaY, 40, accuracy: 1e-9, "pointer up → scroll up")

        let left = AutoScrollController.scrollDelta(from: anchor, to: CGPoint(x: 60, y: 100))
        XCTAssertEqual(left.deltaX, -40, accuracy: 1e-9)
    }

    /// Displacement is virtual and unbounded — the anchor never moves, so any distance maps 1:1.
    func testScrollDeltaUnbounded() {
        let anchor = CGPoint(x: 960, y: 540)
        // A huge "virtual" movement (far beyond any screen) maps linearly — unlimited scrolling.
        let far = AutoScrollController.scrollDelta(from: anchor, to: CGPoint(x: 960, y: 540 + 5000))
        XCTAssertEqual(far.deltaY, -5000, accuracy: 1e-9)
    }

    /// Gain is 1:1 by default.
    func testScrollDeltaGainIsOne() {
        let anchor = CGPoint(x: 0, y: 0)
        let d = AutoScrollController.scrollDelta(from: anchor, to: CGPoint(x: 10, y: -10))
        XCTAssertEqual(d.deltaX, 10, accuracy: 1e-9)
        XCTAssertEqual(d.deltaY, 10, accuracy: 1e-9)
    }
}
