import Foundation

/// Tap-thread state machine used while Settings is learning a mouse-button gesture.
final class ButtonCaptureRecognizer {
    struct Result: Equatable, Sendable {
        let buttonNumber: Int
        let trigger: ButtonTrigger
    }

    private enum State {
        case idle
        case pressed(button: Int, firstDown: Double, holdDeadline: Double)
        case waitingForSecondPress(button: Int, clickDeadline: Double)
    }

    var doubleClickInterval = 0.26
    var holdDuration = 0.50
    private var state: State = .idle

    var nextDeadline: Double? {
        switch state {
        case let .pressed(_, _, deadline), let .waitingForSecondPress(_, deadline): return deadline
        case .idle: return nil
        }
    }

    func start() { state = .idle }

    func buttonDown(_ button: Int, at now: Double) -> Result? {
        switch state {
        case .idle:
            let holdDeadline = now + holdDuration
            state = .pressed(button: button, firstDown: now, holdDeadline: holdDeadline)
            NSLog("Mousse: capture button %d down at %.6f, hold deadline %.6f",
                  button, now, holdDeadline)
        case let .waitingForSecondPress(candidate, deadline):
            guard button == candidate else { return nil }
            state = .idle
            if now <= deadline {
                return Result(buttonNumber: button, trigger: .doubleClick)
            }
            return Result(buttonNumber: candidate, trigger: .click)
        default:
            break
        }
        return nil
    }

    func buttonUp(_ button: Int, at now: Double) -> Result? {
        guard case let .pressed(candidate, firstDown, _) = state, button == candidate else { return nil }
        let deadline = firstDown + doubleClickInterval
        if now >= deadline {
            state = .idle
            return Result(buttonNumber: button, trigger: .click)
        }
        state = .waitingForSecondPress(button: button, clickDeadline: deadline)
        NSLog("Mousse: capture button %d up at %.6f, double-click deadline %.6f",
              button, now, deadline)
        return nil
    }

    func advance(to now: Double) -> Result? {
        switch state {
        case let .pressed(button, _, deadline) where now >= deadline:
            state = .idle
            return Result(buttonNumber: button, trigger: .hold)
        case let .waitingForSecondPress(button, deadline) where now >= deadline:
            state = .idle
            return Result(buttonNumber: button, trigger: .click)
        default:
            return nil
        }
    }

    func cancel() { state = .idle }
}
