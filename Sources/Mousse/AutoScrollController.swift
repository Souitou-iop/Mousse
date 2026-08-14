import CoreGraphics
import Foundation

/// Windows-style auto-scroll mode, ANCHORED variant: a button trigger (click / double-click /
/// hold — whichever the user mapped) TOGGLES the mode. While active the pointer is frozen at the
/// position where the mode was entered (via PointerFreeze) and VIRTUAL pointer movement is turned
/// into scrolling.
///
/// Anchoring solves two problems of free-pointer auto-scroll:
///   1. The scroll target stays fixed: synthetic scroll events dispatch to the anchor, so nested
///      scroll areas (an AI chat box in a browser page, a code panel, …) keep receiving the
///      scroll no matter how far the user "moves" — no per-app adaptation.
///   2. Unlimited scrolling: the displacement is virtual and unbounded — the user can scroll a
///      long page without ever running out of pointer travel.
///
/// The engine feeds every virtual movement into `ScrollAnimator.addPixels`, so output is eased on
/// the display link like real wheel input.
///
/// State is touched only on the event-tap thread, like the other gestures — no locking.
final class AutoScrollController {

    /// Virtual pointer pixels → scroll pixels (1:1). Kept as a constant so the feel can be tuned
    /// in one place without touching the engine.
    static let gain = 1.0

    private(set) var isActive = false

    /// Enter/exit the mode.
    func toggle() {
        isActive.toggle()
    }

    /// Abandon the mode (sleep/wake, device change, app quit paths).
    func cancel() {
        isActive = false
    }

    /// Virtual displacement → signed scroll deltas (positive deltaY = wheel-up / scroll up;
    /// positive deltaX = scroll right). Pointer right → scroll right; pointer down → scroll down.
    static func scrollDelta(from anchor: CGPoint, to pos: CGPoint) -> (deltaX: Double, deltaY: Double) {
        ((pos.x - anchor.x) * AutoScrollController.gain,
         (anchor.y - pos.y) * AutoScrollController.gain)
    }
}
