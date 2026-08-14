import CoreGraphics
import Foundation

/// Windows-style auto-scroll mode: a button trigger (click / double-click / hold, whichever the
/// user mapped) TOGGLES the mode. While active, MOVING THE POINTER scrolls the page in that
/// direction — pointer up scrolls up, pointer down scrolls down, left/right likewise. Triggering
/// again exits the mode. The real wheel keeps working while the mode is active.
///
/// Pure state machine so it is unit-testable. The engine polls the pointer position on its
/// ~30 Hz periodic tick (same ticker as edge scrolling — no extra event-tap mask needed), feeds
/// `tick(pointer:)`, and posts the returned scroll deltas itself.
///
/// State is touched only on the event-tap thread, like the other gestures — no locking.
final class AutoScrollController {

    /// Pointer pixels → scroll pixels (1:1). Kept as a constant so the feel can be tuned in one
    /// place without touching the engine.
    static let gain = 1.0

    private(set) var isActive = false
    private var lastPointer = CGPoint.zero
    private var hasAnchor = false

    /// Enter/exit the mode. Entering anchors the pointer so the position AT the trigger produces
    /// no scroll burst.
    func toggle() {
        isActive.toggle()
        hasAnchor = false
    }

    /// Abandon the mode (sleep/wake, device change, app quit paths).
    func cancel() {
        isActive = false
        hasAnchor = false
    }

    /// One periodic tick. Returns the signed scroll pixels since the last tick (positive =
    /// wheel-up convention for the vertical axis, positive horizontal = scroll right).
    /// (0, 0) when inactive or the pointer hasn't moved.
    func tick(pointer: CGPoint) -> (deltaX: Double, deltaY: Double) {
        guard isActive else { return (0, 0) }
        if !hasAnchor {
            lastPointer = pointer
            hasAnchor = true
            return (0, 0)
        }
        let dx = pointer.x - lastPointer.x
        let dy = pointer.y - lastPointer.y
        lastPointer = pointer
        // Pointer down (dy > 0) → see content below → scroll down (negative wheel delta).
        return (dx * AutoScrollController.gain, -dy * AutoScrollController.gain)
    }
}
