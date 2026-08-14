import XCTest
@testable import Mousse

final class EdgeScrollDetectorTests: XCTestCase {

    private let bounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let width = EdgeScrollDetector.edgeWidth
    private let delay = EdgeScrollDetector.activationDelay

    /// Resting on the bottom edge long enough starts downward scrolling at speed × dt.
    func testBottomEdgeScrollsDownAfterDelay() {
        var d = EdgeScrollDetector()
        let bottom = CGPoint(x: 960, y: bounds.maxY - 1)
        // enter the band
        XCTAssertEqual(d.tick(pointer: bottom, screenBounds: bounds, now: 10,
                              lastRealWheelAt: 0, speed: 400), 0)
        // rest past the delay: activation tick establishes the baseline
        XCTAssertEqual(d.tick(pointer: bottom, screenBounds: bounds, now: 10 + delay + 0.01,
                              lastRealWheelAt: 0, speed: 400), 0)
        XCTAssertTrue(d.isScrolling)
        // subsequent ticks emit speed × dt, negative = down
        let delta = d.tick(pointer: bottom, screenBounds: bounds, now: 10 + delay + 0.01 + 1.0 / 30.0,
                           lastRealWheelAt: 0, speed: 400)
        XCTAssertEqual(delta, -400.0 / 30.0, accuracy: 1e-6)
    }

    /// Top edge scrolls up (positive delta).
    func testTopEdgeScrollsUp() {
        var d = EdgeScrollDetector()
        let top = CGPoint(x: 960, y: bounds.minY + 1)
        _ = d.tick(pointer: top, screenBounds: bounds, now: 10, lastRealWheelAt: 0, speed: 400)
        _ = d.tick(pointer: top, screenBounds: bounds, now: 10 + delay + 0.01, lastRealWheelAt: 0, speed: 400)
        let delta = d.tick(pointer: top, screenBounds: bounds, now: 10 + delay + 0.01 + 1.0 / 30.0,
                           lastRealWheelAt: 0, speed: 400)
        XCTAssertEqual(delta, 400.0 / 30.0, accuracy: 1e-6)
    }

    /// Not enough rest: no scrolling yet.
    func testNoScrollBeforeDelay() {
        var d = EdgeScrollDetector()
        let bottom = CGPoint(x: 960, y: bounds.maxY - 1)
        _ = d.tick(pointer: bottom, screenBounds: bounds, now: 10, lastRealWheelAt: 0, speed: 400)
        XCTAssertEqual(d.tick(pointer: bottom, screenBounds: bounds, now: 10 + delay / 2,
                              lastRealWheelAt: 0, speed: 400), 0)
        XCTAssertFalse(d.isScrolling)
    }

    /// Leaving the edge band resets everything.
    func testLeavingEdgeResets() {
        var d = EdgeScrollDetector()
        let bottom = CGPoint(x: 960, y: bounds.maxY - 1)
        _ = d.tick(pointer: bottom, screenBounds: bounds, now: 10, lastRealWheelAt: 0, speed: 400)
        _ = d.tick(pointer: bottom, screenBounds: bounds, now: 10 + delay + 0.01, lastRealWheelAt: 0, speed: 400)
        XCTAssertTrue(d.isScrolling)
        // pointer moves into the middle of the screen
        XCTAssertEqual(d.tick(pointer: CGPoint(x: 960, y: 540), screenBounds: bounds, now: 10.5,
                              lastRealWheelAt: 0, speed: 400), 0)
        XCTAssertFalse(d.isScrolling)
        // re-entering restarts the delay from scratch
        XCTAssertEqual(d.tick(pointer: bottom, screenBounds: bounds, now: 10.6,
                              lastRealWheelAt: 0, speed: 400), 0)
        XCTAssertFalse(d.isScrolling)
    }

    /// A real wheel input during the rest window restarts the timer; wheel input while scrolling
    /// stops it until the pointer rests again.
    func testRealWheelInputRestartsRestTimer() {
        var d = EdgeScrollDetector()
        let bottom = CGPoint(x: 960, y: bounds.maxY - 1)
        _ = d.tick(pointer: bottom, screenBounds: bounds, now: 10, lastRealWheelAt: 0, speed: 400)
        // wheel tick at 10.2 — later than the band entry (10.0)
        _ = d.tick(pointer: bottom, screenBounds: bounds, now: 10.2, lastRealWheelAt: 10.2, speed: 400)
        // even past the nominal delay (10.2 + 0.5), the rest window restarted at 10.2
        XCTAssertEqual(d.tick(pointer: bottom, screenBounds: bounds, now: 10.2 + delay - 0.1,
                              lastRealWheelAt: 10.2, speed: 400), 0)
        XCTAssertFalse(d.isScrolling)
    }

    /// Middle of the screen: never scrolls.
    func testMiddleOfScreenNeverScrolls() {
        var d = EdgeScrollDetector()
        for now in stride(from: 10.0, through: 11.0, by: 0.2) {
            XCTAssertEqual(d.tick(pointer: CGPoint(x: 960, y: 540), screenBounds: bounds,
                                  now: now, lastRealWheelAt: 0, speed: 400), 0)
        }
        XCTAssertFalse(d.isScrolling)
    }
}
