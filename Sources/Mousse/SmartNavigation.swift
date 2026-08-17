import AppKit
import CoreGraphics

enum SmartNavigation {
    enum Direction: Equatable, Sendable { case back, forward }
    enum Strategy: Equatable { case mouseButton, navigationSwipe, commandBracket }

    static let syntheticTag: Int64 = 0x4D4F_5553_5345 // "MOUSSE"
    private static let cursorApp = CursorAppResolver()

    private enum NavigationField {
        static let eventType = CGEventField(rawValue: 55)!
        static let subtype = CGEventField(rawValue: 110)!
        static let direction = CGEventField(rawValue: 115)!
        static let phase = CGEventField(rawValue: 132)!
    }

    private enum NavigationValue {
        static let gestureEvent: Int64 = 29
        static let navigationSwipe: Int64 = 6
        static let phaseBegan: Int64 = 1
        static let phaseEnded: Int64 = 4
        static let swipeNone: Int64 = 0
        static let swipeLeft: Int64 = 1 << 2
        static let swipeRight: Int64 = 1 << 3
    }

    static func post(_ direction: Direction) {
        // Never inject a HID gesture while the physical-button event tap is still in its callback.
        // Mac Mouse Fix deliberately defers universal navigation to the main queue for the same
        // reason; Finder drops a Navigation Swipe posted re-entrantly from that callback.
        dispatchOnMain {
            postOnMain(direction)
        }
    }

    static func dispatchOnMain(_ work: @escaping () -> Void) {
        DispatchQueue.main.async(execute: work)
    }

    private static func postOnMain(_ direction: Direction) {
        let location = CGEvent(source: nil)?.location ?? .zero
        let windowTarget = cursorApp.navigationTarget(at: location)
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let frontmostBundleID = frontmostApp?.bundleIdentifier
        let bundleID = navigationTarget(
            windowBundleID: windowTarget?.bundleID,
            frontmostBundleID: frontmostBundleID)

        let targetPID = windowTarget?.pid ?? frontmostApp?.processIdentifier
        activateTargetAppIfNeeded(pid: targetPID)

        let selectedStrategy = strategy(for: bundleID)
        switch selectedStrategy {
        case .mouseButton:
            makeMouseButtonEvents(direction, location: location).forEach {
                $0.post(tap: .cgSessionEventTap)
            }
        case .navigationSwipe:
            postNavigationSwipe(direction)
        case .commandBracket:
            postCommandBracket(direction)
        }
    }

    static func activateTargetAppIfNeeded(pid: pid_t?) {
        guard let pid,
              let targetApp = NSRunningApplication(processIdentifier: pid),
              !targetApp.isActive else { return }
        targetApp.activate()
    }

    static func navigationTarget(windowBundleID: String?, frontmostBundleID: String?) -> String? {
        if let windowBundleID, !windowBundleID.isEmpty { return windowBundleID }
        if let frontmostBundleID, !frontmostBundleID.isEmpty { return frontmostBundleID }
        return nil
    }

    /// Finder uses its native history commands; compatible Apple apps use the same Navigation Swipe
    /// gesture as Safari. Non-Apple apps keep receiving standard side buttons, which is the
    /// compatible path for Chromium and Electron apps.
    static func strategy(for bundleID: String?) -> Strategy {
        guard let bundleID, !bundleID.isEmpty else { return .mouseButton }
        // Finder and Safari expose Back/Forward as Command-[ and Command-]. On this OS, WindowServer
        // accepts a Navigation Swipe posted by Mousse but these apps ignore it, even when the event
        // is emitted through the same CoreGraphics C sequence as Mac Mouse Fix. Use their native
        // history commands.
        if bundleID == "com.apple.finder" || bundleID == "com.apple.Safari" { return .commandBracket }
        if bundleID.hasPrefix("com.operasoftware.Opera") ||
            bundleID.hasPrefix("com.binarynights.ForkLift") {
            return .navigationSwipe
        }
        return bundleID.hasPrefix("com.apple.") ? .navigationSwipe : .mouseButton
    }

    static func makeMouseButtonEvents(_ direction: Direction, location: CGPoint = .zero) -> [CGEvent] {
        let buttonNumber: Int64 = direction == .back ? 3 : 4
        let point = location == .zero ? (CGEvent(source: nil)?.location ?? .zero) : location
        let source = CGEventSource(stateID: .hidSystemState)
        return [CGEventType.otherMouseDown, .otherMouseUp].compactMap { type in
            let event = CGEvent(mouseEventSource: source, mouseType: type,
                                mouseCursorPosition: point, mouseButton: .center)
            event?.setIntegerValueField(.mouseEventButtonNumber, value: buttonNumber)
            event?.setIntegerValueField(.mouseEventClickState, value: 1)
            event?.setIntegerValueField(.eventSourceUserData, value: syntheticTag)
            return event
        }
    }

    /// Swift reimplementation of Mac Mouse Fix's minimal Navigation Swipe sequence. The same event
    /// is posted for began and ended because WindowServer does not reliably accept two separately
    /// created gesture events here. This behavior is derived from Mac Mouse Fix's TouchSimulator.
    static func makeNavigationSwipeEvent(_ direction: Direction) -> CGEvent? {
        guard let event = CGEvent(source: nil) else { return nil }
        event.setIntegerValueField(NavigationField.eventType, value: NavigationValue.gestureEvent)
        event.setIntegerValueField(NavigationField.subtype, value: NavigationValue.navigationSwipe)
        event.setIntegerValueField(NavigationField.phase, value: NavigationValue.phaseBegan)
        event.setIntegerValueField(NavigationField.direction,
                                   value: direction == .back ? NavigationValue.swipeLeft
                                                             : NavigationValue.swipeRight)
        return event
    }

    static func finishNavigationSwipeEvent(_ event: CGEvent) {
        event.setIntegerValueField(NavigationField.direction, value: NavigationValue.swipeNone)
        event.setIntegerValueField(NavigationField.phase, value: NavigationValue.phaseEnded)
    }

    private static func postNavigationSwipe(_ direction: Direction) {
        guard let event = makeNavigationSwipeEvent(direction) else { return }
        event.post(tap: .cghidEventTap)
        finishNavigationSwipeEvent(event)
        event.post(tap: .cghidEventTap)
    }

    private static func postCommandBracket(_ direction: Direction) {
        let keyCode: UInt16 = direction == .back ? 0x21 : 0x1E // ANSI [ and ]
        RemapAction.keyStroke(keyCode: keyCode, control: false, option: false,
                              command: true, shift: false).post()
    }
}
