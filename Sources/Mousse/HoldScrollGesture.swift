import Foundation

/// "Hold & scroll" (MMF-style click-and-scroll): while a configured button is held, wheel input is
/// converted into a continuous output — volume ±1 step per notch — instead of scrolling the page.
///
/// The button's mapping is `trigger == .hold` with a `.scrollOutput` action. Pressing the button
/// enters the mode IMMEDIATELY (no hold-duration wait: adjusting the volume must respond at once),
/// releasing ends it. The engine routes the button's down/up and every wheel event here and
/// swallows them while the mode is active. `ScrollOutput` is the extension point (first
/// implementation: volume only).
///
/// State is touched only on the event-tap thread, like SpaceDragGesture — no locking.
final class HoldScrollGesture {

    /// What wheel input drives while the button is held; nil = not configured (never activates).
    var output: RemapAction.ScrollOutput?

    /// Injectable for tests; the engine wires it to `MediaKey.post()`. `steps` is ±1 per notch.
    var volumeStep: (Int) -> Void = { _ in }

    private(set) var isActive = false

    /// Begin holding the configured button. Returns true if this button is ours (the caller should
    /// swallow the button-down). Enters the mode immediately.
    func handleButtonDown(buttonNumber: Int) -> Bool {
        guard output != nil else { return false }
        isActive = true
        return true
    }

    /// Release. Returns true if this button was ours (the caller should swallow the button-up).
    func handleButtonUp(buttonNumber: Int) -> Bool {
        guard isActive else { return false }
        isActive = false
        return true
    }

    /// One wheel notch while active: convert it to the output. Returns true if consumed.
    func handleScroll(lineDelta: Double) -> Bool {
        guard isActive else { return false }
        volumeStep(lineDelta > 0 ? 1 : -1)
        return true
    }

    /// Abandon the mode (sleep/wake, device change) so a lost button-up can't wedge it active.
    func cancel() {
        isActive = false
    }
}
