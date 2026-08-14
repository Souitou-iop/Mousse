import CoreGraphics
import Foundation

/// Windows-style auto-scroll mode: a button trigger (click / double-click / hold — whichever the
/// user mapped) TOGGLES the mode.
///
/// Behavior matches Windows (Chrome/Edge middle-button auto-scroll):
///   • Entering the mode records the pointer position as the anchor;
///   • Moving the pointer AWAY from the anchor scrolls continuously in that direction — pointer
///     above the anchor scrolls up, below scrolls down, left/right likewise;
///   • The scroll CONTINUES automatically (the user does not have to keep moving the mouse);
///     the further the pointer is from the anchor, the faster it scrolls;
///   • Moving the pointer back into the dead zone around the anchor stops scrolling;
///   • The pointer is fully free — never locked or warped;
///   • Triggering again exits the mode. The real wheel keeps working while the mode is active.
///
/// The pointer's offset from the anchor is polled on the engine's ~30 Hz tick; the returned
/// deltas are fed into `ScrollAnimator.addPixels` so the output is eased on the display link like
/// real wheel input.
///
/// State is touched only on the event-tap thread, like the other gestures — no locking.
final class AutoScrollController {

    /// Scroll speed cap — extreme offsets must not fling the page.
    static let maxSpeed = 4000.0
    /// Pointer offset below which scrolling stops (px).
    static let deadzone = 6.0

    private(set) var isActive = false
    private var anchor: CGPoint?
    private var lastTickAt = 0.0

    /// Enter/exit the mode. (Re-)entering re-anchors on the next tick.
    func toggle() {
        isActive.toggle()
        anchor = nil
    }

    /// Abandon the mode (sleep/wake, device change, app quit paths).
    func cancel() {
        isActive = false
        anchor = nil
    }

    /// One periodic tick. `speed` is the user's auto-scroll acceleration — scroll px/s per px of
    /// pointer offset from the anchor. `baseSpeed` is the scroll rate applied as soon as the
    /// pointer leaves the dead zone, so even a small nudge gets a usable speed. Returns the signed
    /// scroll pixels since the last tick (positive deltaY = wheel-up / scroll up; positive deltaX =
    /// scroll right). Non-zero whenever the pointer is outside the dead zone — i.e. scrolling
    /// continues automatically while the pointer rests.
    func tick(pointer: CGPoint, now: Double, speed: Double, baseSpeed: Double = 0) -> (deltaX: Double, deltaY: Double) {
        guard isActive else { return (0, 0) }
        if anchor == nil {
            anchor = pointer
            lastTickAt = now
            return (0, 0)
        }
        let dt = min(max(now - lastTickAt, 0), 0.1) // clamp a stalled tick so a pause can't dump a burst
        lastTickAt = now

        func speedOf(_ offset: CGFloat) -> Double {
            guard abs(offset) > AutoScrollController.deadzone else { return 0 }
            let sign = offset > 0 ? 1.0 : -1.0
            let raw = sign * baseSpeed + Double(offset) * speed
            return min(max(raw, -AutoScrollController.maxSpeed), AutoScrollController.maxSpeed)
        }

        // Pointer above the anchor (y smaller) → positive offset → scroll up; right → scroll right.
        let offX = pointer.x - anchor!.x
        let offY = anchor!.y - pointer.y
        return (speedOf(offX) * dt, speedOf(offY) * dt)
    }
}
