import Foundation

/// Tap-thread state machine for click, double-click, and hold mappings.
final class ButtonTriggerRecognizer {
    enum ClickPolicy: Equatable {
        case automatic
        case deferredUntilRelease
        case confirmed(delay: Double)
    }

    struct Actions: Equatable {
        var click: RemapAction?
        var doubleClick: RemapAction?
        var hold: RemapAction?

        init(click: RemapAction? = nil, doubleClick: RemapAction? = nil,
             hold: RemapAction? = nil) {
            self.click = click
            self.doubleClick = doubleClick
            self.hold = hold
        }

        var isEmpty: Bool { click == nil && doubleClick == nil && hold == nil }
    }

    struct TriggeredAction: Equatable {
        let button: Int
        let action: RemapAction
    }

    struct Output: Equatable {
        var triggered: [TriggeredAction] = []
    }

    private struct State {
        var actions: Actions
        var isDown = false
        var firstDownTime = 0.0
        var holdDeadline: Double?
        var clickDeadline: Double?
        var waitingForSecondClick = false
        var isSecondPress = false
        var resolved = false
        var clickPolicy = ClickPolicy.automatic
    }

    var doubleClickInterval = 0.26
    var holdDuration = 0.50
    private var states: [Int: State] = [:]

    var nextDeadline: Double? {
        states.values.flatMap { [$0.holdDeadline, $0.clickDeadline].compactMap { $0 } }.min()
    }

    func buttonDown(_ button: Int, at now: Double, actions: Actions,
                    clickPolicy: ClickPolicy = .automatic) -> Output {
        var output = advance(to: now)
        guard !actions.isEmpty else { return output }

        if var state = states[button], state.waitingForSecondClick,
           let deadline = state.clickDeadline, now <= deadline {
            state.isDown = true
            state.waitingForSecondClick = false
            state.isSecondPress = true
            state.clickDeadline = nil
            state.holdDeadline = (state.actions.hold != nil || state.clickPolicy.isConfirmed)
                ? now + holdDuration : nil
            state.resolved = false
            states[button] = state
            return output
        }

        var state = State(actions: actions, isDown: true, firstDownTime: now,
                          clickPolicy: clickPolicy)
        if actions.hold != nil || clickPolicy.isConfirmed {
            state.holdDeadline = now + holdDuration
        }
        if actions.click != nil, actions.doubleClick == nil, actions.hold == nil,
           clickPolicy == .automatic {
            output.triggered.append(TriggeredAction(button: button, action: actions.click!))
            state.resolved = true
        }
        states[button] = state
        return output
    }

    func buttonUp(_ button: Int, at now: Double) -> Output {
        var output = advance(to: now)
        guard var state = states[button] else { return output }
        state.isDown = false
        state.holdDeadline = nil

        if state.resolved {
            states.removeValue(forKey: button)
        } else if state.isSecondPress {
            if let action = state.actions.doubleClick {
                output.triggered.append(TriggeredAction(button: button, action: action))
            }
            states.removeValue(forKey: button)
        } else if state.actions.doubleClick != nil || state.clickPolicy.isConfirmed {
            let deadline = state.actions.doubleClick != nil
                ? now + doubleClickInterval
                : now + state.clickPolicy.confirmationDelay
            if now >= deadline {
                if let action = state.actions.click {
                    output.triggered.append(TriggeredAction(button: button, action: action))
                }
                states.removeValue(forKey: button)
            } else {
                state.waitingForSecondClick = true
                state.clickDeadline = deadline
                states[button] = state
            }
        } else {
            if let action = state.actions.click {
                output.triggered.append(TriggeredAction(button: button, action: action))
            }
            states.removeValue(forKey: button)
        }
        return output
    }

    func advance(to now: Double) -> Output {
        var output = Output()
        for button in Array(states.keys) {
            guard var state = states[button] else { continue }
            if state.isDown, !state.resolved,
               let deadline = state.holdDeadline, now >= deadline {
                if let action = state.actions.hold {
                    output.triggered.append(TriggeredAction(button: button, action: action))
                }
                state.resolved = true
                state.holdDeadline = nil
                state.clickDeadline = nil
                state.waitingForSecondClick = false
                states[button] = state
            } else if !state.isDown, state.waitingForSecondClick,
                      let deadline = state.clickDeadline, now >= deadline {
                if let action = state.actions.click {
                    output.triggered.append(TriggeredAction(button: button, action: action))
                }
                states.removeValue(forKey: button)
            }
        }
        return output
    }

    func cancel(button: Int) {
        states.removeValue(forKey: button)
    }

    /// Whether this button currently has recognizer state. Lets the engine swallow the matching
    /// button-up even if the app under the cursor changed between down and up.
    func isTracking(_ button: Int) -> Bool {
        states[button] != nil
    }

    func cancelAll() {
        states.removeAll()
    }
}

private extension ButtonTriggerRecognizer.ClickPolicy {
    var isConfirmed: Bool {
        if case .confirmed = self { return true }
        return false
    }

    var confirmationDelay: Double {
        if case let .confirmed(delay) = self { return delay }
        return 0
    }
}
