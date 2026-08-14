import XCTest
@testable import Mousse

final class AutoScrollControllerTests: XCTestCase {

    private func tick(_ c: AutoScrollController, _ x: CGFloat, _ y: CGFloat, at now: Double = 10.0,
                      speed: Double = 1.0) -> (deltaX: Double, deltaY: Double) {
        c.tick(pointer: CGPoint(x: x, y: y), now: now, speed: speed)
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

    /// Cancel (sleep/wake, device change) exits the mode.
    func testCancelExits() {
        let c = AutoScrollController()
        c.toggle()
        XCTAssertTrue(c.isActive)
        c.cancel()
        XCTAssertFalse(c.isActive)
    }

    /// The first tick after entering anchors; the anchor position itself produces no scroll.
    func testFirstTickAnchors() {
        let c = AutoScrollController()
        c.toggle()
        XCTAssertEqual(tick(c, 100, 100).deltaY, 0) // anchors here
        XCTAssertEqual(tick(c, 100, 100).deltaY, 0) // still on the anchor → dead zone
    }

    // MARK: - Direction & speed from the offset

    /// Pointer above the anchor → scrolls up (positive); below → down (negative).
    func testVerticalDirectionFollowsOffset() {
        let c = AutoScrollController()
        c.toggle()
        _ = tick(c, 100, 100, at: 10.0) // anchor
        let up = tick(c, 100, 80, at: 10.0 + 1.0 / 30.0)
        XCTAssertGreaterThan(up.deltaY, 0, "pointer above anchor → scroll up")
        let down = tick(c, 100, 130, at: 10.0 + 2.0 / 30.0)
        XCTAssertLessThan(down.deltaY, 0, "pointer below anchor → scroll down")
    }

    /// Pointer right of the anchor → scrolls right; left → left.
    func testHorizontalDirectionFollowsOffset() {
        let c = AutoScrollController()
        c.toggle()
        _ = tick(c, 100, 100, at: 10.0) // anchor
        let right = tick(c, 150, 100, at: 10.0 + 1.0 / 30.0)
        XCTAssertGreaterThan(right.deltaX, 0, "pointer right of anchor → scroll right")
        let left = tick(c, 60, 100, at: 10.0 + 2.0 / 30.0)
        XCTAssertLessThan(left.deltaX, 0, "pointer left of anchor → scroll left")
    }

    /// Speed grows with the offset: 100 px offset scrolls at 100 px/s (gain 1).
    func testSpeedProportionalToOffset() {
        let c = AutoScrollController()
        c.toggle()
        _ = tick(c, 100, 100, at: 10.0) // anchor
        _ = tick(c, 100, 0, at: 10.0 + 1.0 / 30.0) // 100 px above
        let d = tick(c, 100, 0, at: 10.0 + 2.0 / 30.0)
        XCTAssertEqual(d.deltaY, 100.0 / 30.0, accuracy: 1e-6)
    }

    /// The user's speed setting scales the response linearly.
    func testSpeedSettingScales() {
        let c = AutoScrollController()
        c.toggle()
        _ = tick(c, 100, 100, at: 10.0) // anchor
        _ = tick(c, 100, 80, at: 10.0 + 1.0 / 30.0, speed: 2.0) // 20 px offset × 2
        let d = tick(c, 100, 80, at: 10.0 + 2.0 / 30.0, speed: 2.0)
        XCTAssertEqual(d.deltaY, 40.0 / 30.0, accuracy: 1e-6)
    }

    /// Inside the dead zone no scrolling happens.
    func testDeadzoneStopsScrolling() {
        let c = AutoScrollController()
        c.toggle()
        _ = tick(c, 100, 100, at: 10.0) // anchor
        let d = tick(c, 100, 104, at: 10.0 + 1.0 / 30.0) // 4 px offset < deadzone
        XCTAssertEqual(d.deltaY, 0)
    }

    /// Extreme offsets are capped at maxSpeed.
    func testSpeedCapped() {
        let c = AutoScrollController()
        c.toggle()
        _ = tick(c, 100, 100, at: 10.0)
        _ = tick(c, 100, -100_000, at: 10.0 + 1.0 / 30.0)
        let d = tick(c, 100, -100_000, at: 10.0 + 2.0 / 30.0)
        XCTAssertLessThanOrEqual(d.deltaY, AutoScrollController.maxSpeed / 30.0 + 1e-9)
        XCTAssertGreaterThan(d.deltaY, 0)
    }

    // MARK: - Continuous scrolling (the Windows behavior)

    /// The scroll CONTINUES while the pointer rests outside the dead zone — the user moves the
    /// mouse once, the page keeps scrolling (this is the core of Windows auto-scroll).
    func testScrollingContinuesWhilePointerRests() {
        let c = AutoScrollController()
        c.toggle()
        _ = tick(c, 100, 100, at: 10.0) // anchor
        _ = tick(c, 100, 60, at: 10.0 + 1.0 / 30.0)  // move 40 px up, then rest
        var last = 0.0
        for i in 2...20 { // pointer does NOT move; scroll must keep coming
            let d = tick(c, 100, 60, at: 10.0 + Double(i) / 30.0)
            XCTAssertGreaterThan(d.deltaY, 0, "must keep scrolling while resting (tick \(i))")
            XCTAssertEqual(d.deltaY, 40.0 / 30.0, accuracy: 1e-6)
            last = d.deltaY
        }
        XCTAssertGreaterThan(last, 0)
    }

    /// Moving the pointer back to (or near) the anchor stops the scrolling.
    func testReturningToAnchorStops() {
        let c = AutoScrollController()
        c.toggle()
        _ = tick(c, 100, 100, at: 10.0) // anchor
        _ = tick(c, 100, 60, at: 10.0 + 1.0 / 30.0) // scroll up
        let stop = tick(c, 100, 98, at: 10.0 + 2.0 / 30.0) // back inside the dead zone
        XCTAssertEqual(stop.deltaY, 0)
    }

    /// Moving across the anchor reverses direction.
    func testCrossingAnchorReverses() {
        let c = AutoScrollController()
        c.toggle()
        _ = tick(c, 100, 100, at: 10.0)
        let up = tick(c, 100, 50, at: 10.0 + 1.0 / 30.0)
        XCTAssertGreaterThan(up.deltaY, 0)
        let down = tick(c, 100, 150, at: 10.0 + 2.0 / 30.0)
        XCTAssertLessThan(down.deltaY, 0)
    }
}
