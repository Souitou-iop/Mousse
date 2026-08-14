import CoreGraphics
import Foundation

/// Drives "edge scrolling": when the pointer rests against the top or bottom screen edge, the page
/// scrolls continuously in that direction; leaving the edge — or rolling the real wheel — stops
/// it. Vertical only for now; the left/right edges are a later extension.
///
/// Pure state machine so it is unit-testable. The engine feeds it one timer tick with the current
/// pointer location, the screen bounds and the timestamp of the last REAL wheel input, then posts
/// the returned scroll pixels itself.
struct EdgeScrollDetector {

    static let edgeWidth = 8.0       // px from the edge that counts as "resting on the edge"
    static let activationDelay = 0.5 // s of uninterrupted rest before scrolling starts

    /// Positive delta scrolls up (wheel-up convention), negative scrolls down.
    private(set) var isScrolling = false
    private var edgeEnteredAt: Double? // when the pointer entered the edge band (nil = not in band)
    private var lastTickAt = 0.0

    /// One timer tick. `now` and `lastRealWheelAt` are CACurrentMediaTime values.
    /// Returns the signed pixels to emit this tick (0 when not scrolling).
    mutating func tick(pointer: CGPoint, screenBounds: CGRect, now: Double,
                       lastRealWheelAt: Double, speed: Double) -> Double {
        let inTopBand = pointer.y <= screenBounds.minY + EdgeScrollDetector.edgeWidth
        let inBottomBand = pointer.y >= screenBounds.maxY - EdgeScrollDetector.edgeWidth
        let band: Int = inTopBand ? 1 : (inBottomBand ? -1 : 0)

        if band == 0 {
            reset()
            return 0
        }

        // Real wheel input takes priority: the user is actively scrolling — restart the rest
        // timer, so edge scrolling only resumes after the wheel has been quiet again.
        if lastRealWheelAt > (edgeEnteredAt ?? 0) {
            edgeEnteredAt = now
            lastTickAt = now
            isScrolling = false
            return 0
        }

        if edgeEnteredAt == nil {
            edgeEnteredAt = now
            lastTickAt = now
            return 0
        }
        guard now - edgeEnteredAt! >= EdgeScrollDetector.activationDelay else { return 0 }

        let dt = min(max(now - lastTickAt, 0), 0.1) // clamp a stalled tick so a pause can't dump a burst
        lastTickAt = now
        if !isScrolling {
            isScrolling = true
            lastTickAt = now // first active tick establishes the baseline; emit from the next one
            return 0
        }
        return Double(band) * speed * dt
    }

    mutating func reset() {
        isScrolling = false
        edgeEnteredAt = nil
        lastTickAt = 0
    }
}
