import Foundation

/// "Hold & scroll" (MMF-style click-and-scroll): while a configured button is held, wheel input is
/// converted into a continuous output — volume ±1 step per notch — instead of scrolling the page.
///
/// A button is configured with `trigger == .hold` and a `.scrollOutput` action. Pressing THAT
/// button enters the mode IMMEDIATELY (no hold-duration wait: adjusting the volume must respond at
/// once), releasing ends it; other buttons are never affected — `mappings` maps button number →
/// output, and only the configured button's down/up/wheel events are swallowed. `ScrollOutput` is
/// the extension point (first implementation: volume only).
///
/// State is touched only on the event-tap thread, like SpaceDragGesture — no locking.
final class HoldScrollGesture {

    /// Configured buttons and what wheel input drives while each is held. Empty = feature off.
    var mappings: [Int: RemapAction.ScrollOutput] = [:]

    /// Injectable for tests; the engine wires it to `MediaKey.post()`. `steps` is ±1 per notch.
    var volumeStep: (Int) -> Void = { _ in }

    private(set) var isActive = false
    private var activeButton = 0
    private var activeOutput: RemapAction.ScrollOutput?

    /// Begin holding a button. Returns true if this button has a hold-and-scroll mapping (the
    /// caller should swallow the button-down and enter the mode).
    func handleButtonDown(buttonNumber: Int) -> Bool {
        guard let output = mappings[buttonNumber] else { return false }
        activeButton = buttonNumber
        activeOutput = output
        isActive = true
        return true
    }

    /// Release. Returns true if this button was the one holding the mode (swallow the button-up).
    func handleButtonUp(buttonNumber: Int) -> Bool {
        guard isActive, buttonNumber == activeButton else { return false }
        isActive = false
        activeButton = 0
        activeOutput = nil
        return true
    }

    /// One wheel notch while active: convert it to the output. Returns true if consumed.
    func handleScroll(lineDelta: Double) -> Bool {
        guard isActive, activeOutput != nil else { return false }
        volumeStep(lineDelta > 0 ? 1 : -1)
        return true
    }

    /// Abandon the mode (sleep/wake, device change) so a lost button-up can't wedge it active.
    func cancel() {
        isActive = false
        activeButton = 0
        activeOutput = nil
    }
}
