import CoreGraphics
import Foundation

/// Windows-style auto-scroll mode: a button trigger (click / double-click / hold, whichever the
/// user mapped) TOGGLES the mode. While active, MOVING THE POINTER scrolls the page in that
/// direction — pointer up scrolls up, pointer down scrolls down, left/right likewise. Triggering
/// again exits the mode. The real wheel keeps working while the mode is active.
///
/// Unlimited scrolling: the pointer can only move within the screen, so once it runs into an edge
/// the scroll CONTINUES in that direction at the movement speed it had when it hit the edge (edge
/// continuation, all four edges), until the pointer leaves the band.
///
/// Smoothness: the engine feeds the returned deltas into `ScrollAnimator.addPixels`, which eases
/// them on the display link (~120 Hz, sub-pixel) — the same pipeline as wheel smoothing.
///
/// Pure state machine so it is unit-testable; state is touched only on the event-tap thread.
final class AutoScrollController {

    /// Pointer pixels → scroll pixels (1:1). Kept as a constant so the feel can be tuned in one
    /// place without touching the engine.
    static let gain = 1.0

    /// Screen-edge band where edge continuation kicks in (same width as edge scrolling).
    static let edgeWidth = 8.0

    private(set) var isActive = false
    private var lastPointer = CGPoint.zero
    private var hasAnchor = false
    private var lastTickAt = 0.0
    private var lastSpeedX = 0.0 // pointer px/s, from the last non-edge tick
    private var lastSpeedY = 0.0

    /// Enter/exit the mode. Entering anchors the pointer so the position AT the trigger produces
    /// no scroll burst.
    func toggle() {
        isActive.toggle()
        hasAnchor = false
        lastSpeedX = 0
        lastSpeedY = 0
    }

    /// Abandon the mode (sleep/wake, device change, app quit paths).
    func cancel() {
        isActive = false
        hasAnchor = false
        lastSpeedX = 0
        lastSpeedY = 0
    }

    /// One periodic tick. Returns the signed scroll pixels to feed the animator since the last
    /// tick (positive deltaY = wheel-up / scroll up; positive deltaX = scroll right).
    /// (0, 0) when inactive or nothing has moved.
    func tick(pointer: CGPoint, now: Double, screenBounds: CGRect) -> (deltaX: Double, deltaY: Double) {
        guard isActive else { return (0, 0) }
        let dt = hasAnchor ? min(max(now - lastTickAt, 0), 0.1) : 0
        lastTickAt = now
        if !hasAnchor {
            lastPointer = pointer
            hasAnchor = true
            return (0, 0)
        }
        let dx = pointer.x - lastPointer.x
        let dy = pointer.y - lastPointer.y
        lastPointer = pointer

        // Edge continuation: the pointer hit a screen edge — keep scrolling that way at the speed
        // it had when it got there (the sign comes from the edge, not the residual movement).
        let inTop = pointer.y <= screenBounds.minY + AutoScrollController.edgeWidth
        let inBottom = pointer.y >= screenBounds.maxY - AutoScrollController.edgeWidth
        let inLeft = pointer.x <= screenBounds.minX + AutoScrollController.edgeWidth
        let inRight = pointer.x >= screenBounds.maxX - AutoScrollController.edgeWidth
        if inTop || inBottom || inLeft || inRight {
            let vy = inBottom ? -abs(lastSpeedY) : (inTop ? abs(lastSpeedY) : 0)
            let vx = inRight ? abs(lastSpeedX) : (inLeft ? -abs(lastSpeedX) : 0)
            return (vx * dt * AutoScrollController.gain,
                    vy * dt * AutoScrollController.gain)
        }

        if dt > 0 {
            lastSpeedX = dx / dt
            lastSpeedY = dy / dt
        }
        // Pointer down (dy > 0) → see content below → scroll down (negative wheel delta).
        return (dx * AutoScrollController.gain, -dy * AutoScrollController.gain)
    }
}
