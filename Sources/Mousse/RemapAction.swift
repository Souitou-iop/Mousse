import CoreGraphics
import AppKit

/// What a remapped mouse button does. Keystroke actions cover spaces/Mission Control and any custom
/// shortcut; media keys cover volume/playback; `launchpad` opens Launchpad. All via public APIs.
enum RemapAction: Codable, Equatable, Hashable, Sendable {
    case none // placeholder — a mapping whose action hasn't been chosen yet; never fires
    case keyStroke(keyCode: UInt16, control: Bool, option: Bool, command: Bool, shift: Bool)
    case mediaKey(MediaKey)
    case launchpad
    case spotlight
    case siri
    case appSwitcher
    case openApp(path: String, displayName: String)
    case navigateBack
    case navigateForward
    case smartZoom
    case clickButton(buttonNumber: Int) // simulate a click of another button (e.g. the middle button)
    case scrollOutput(ScrollOutput)     // while the button is held, wheel input drives this output
    case autoScroll                     // toggle Windows-style auto-scroll mode (move the pointer to scroll)

    // Keystroke presets (macOS default shortcuts)
    static let spaceLeft      = keyStroke(keyCode: 0x7B, control: true, option: false, command: false, shift: false) // Ctrl+←
    static let spaceRight     = keyStroke(keyCode: 0x7C, control: true, option: false, command: false, shift: false) // Ctrl+→
    static let missionControl = keyStroke(keyCode: 0x7E, control: true, option: false, command: false, shift: false) // Ctrl+↑
    static let appExpose      = keyStroke(keyCode: 0x7D, control: true, option: false, command: false, shift: false) // Ctrl+↓

    /// What a held button turns wheel input into (MMF-style "click and scroll" outputs).
    enum ScrollOutput: String, Codable, CaseIterable, Sendable {
        case volume // one notch up/down = volume +1/−1 step

        var label: String {
            switch self {
            case .volume: return Localized.text("action.holdScrollVolume")
            }
        }
    }

    /// Actions offered in the Settings picker.
    static var presets: [RemapAction] {
        [.navigateBack, .navigateForward, .spaceLeft, .spaceRight, .missionControl, .appExpose, .launchpad,
         .spotlight, .siri, .appSwitcher,
         .smartZoom, .clickButton(buttonNumber: 3), .scrollOutput(.volume), .autoScroll,
         .mediaKey(.volumeDown), .mediaKey(.volumeUp), .mediaKey(.mute),
         .mediaKey(.playPause), .mediaKey(.previous), .mediaKey(.next)]
    }

    /// Serial queue so keystrokes are synthesized OFF the event-tap thread (posting from inside the
    /// tap callback is unreliable for system hotkeys and would stall the tap). A FRESH event source
    /// is made per keystroke so modifier state never accumulates/desyncs across calls — reusing one
    /// source made Space-switching flaky (it worked once, then stopped).
    private static let keyQueue = DispatchQueue(label: "com.mousse.keystroke", qos: .userInteractive)

    /// Perform the action.
    func post() {
        switch self {
        case .none:
            break // unconfigured — the engine excludes these mappings entirely

        case let .keyStroke(code, control, option, command, shift):
            // Mission Control / App Exposé are WindowServer hotkeys that ignore synthetic key events
            // on recent macOS — drive them via the Dock SPI instead (reliable). If the SPI didn't
            // resolve, fall through to the synthesized keystroke below: a real attempt on older
            // macOS beats a silent no-op.
            if control && !option && !command && !shift {
                if SystemActions.isAvailable {
                    if code == 0x7E { SystemActions.missionControl(); return } // Ctrl+Up
                    if code == 0x7D { SystemActions.appExpose();      return } // Ctrl+Down
                }
                // Space switching: drive the symbolic hotkey directly so it works even when the
                // user remapped the "Move left/right a space" keyboard shortcut.
                if code == 0x7B { SystemActions.spaceLeft();  return }     // Ctrl+Left
                if code == 0x7C { SystemActions.spaceRight(); return }     // Ctrl+Right
            }
            // System symbolic hotkeys (Mission Control, Move-Space) only fire when WindowServer sees
            // the REAL modifier keys held WITH matching flags. Press each modifier (flag accumulated
            // on its own event), tap the key, then release — spaced by tiny delays so WindowServer
            // registers the modifier before the key. Done off the tap thread.
            var mods: [(key: CGKeyCode, flag: CGEventFlags)] = []
            if control { mods.append((0x3B, .maskControl)) }
            if shift   { mods.append((0x38, .maskShift)) }
            if option  { mods.append((0x3A, .maskAlternate)) }
            if command { mods.append((0x37, .maskCommand)) }
            let allFlags = mods.reduce(into: CGEventFlags()) { $0.insert($1.flag) }

            RemapAction.keyQueue.async {
                let src = CGEventSource(stateID: .privateState)
                let loc = CGEventTapLocation.cghidEventTap
                var acc = CGEventFlags()
                for m in mods {
                    acc.insert(m.flag)
                    let e = CGEvent(keyboardEventSource: src, virtualKey: m.key, keyDown: true)
                    e?.flags = acc; e?.post(tap: loc)
                    usleep(1500)
                }
                if let down = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true) {
                    down.flags = allFlags; down.post(tap: loc)
                }
                usleep(1500)
                if let up = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false) {
                    up.flags = allFlags; up.post(tap: loc)
                }
                usleep(1500)
                for m in mods.reversed() {
                    acc.remove(m.flag)
                    let e = CGEvent(keyboardEventSource: src, virtualKey: m.key, keyDown: false)
                    e?.flags = acc; e?.post(tap: loc)
                    usleep(800)
                }
            }

        case let .mediaKey(key):
            key.post()

        case .launchpad:
            // MMF-style SHK drive: works on macOS 15 (Launchpad) and 26 (the renamed "Apps" app)
            // without hard-coding app paths. See SystemActions.launchpad().
            SystemActions.launchpad()

        case .spotlight:
            SystemActions.spotlight()

        case .siri:
            SystemActions.siri()

        case .appSwitcher:
            SystemActions.appSwitcher()

        case let .openApp(path, _):
            SystemActions.openApp(path: path)

        case .smartZoom:
            // Trackpad-style "smart zoom" toggle (double-tap two fingers): Safari/Preview/etc.
            // zoom to fit. One field-based gesture event (kIOHIDEventTypeZoomToggle); macOS 27
            // ignores these fields like the other field-based gestures.
            guard let event = CGEvent(source: nil) else { return }
            event.setIntegerValueField(CGEventField(rawValue: 55)!, value: 29)   // NSEventTypeGesture
            event.setIntegerValueField(CGEventField(rawValue: 110)!, value: 22)  // kIOHIDEventTypeZoomToggle
            event.post(tap: .cghidEventTap)

        case let .clickButton(buttonNumber):
            // Simulate a real click of another button (e.g. the middle button). Tagged so our own
            // tap passes it through instead of re-mapping it.
            let cgButton: CGMouseButton = switch buttonNumber {
            case 1: .left
            case 2: .right
            default: .center
            }
            let src = CGEventSource(stateID: .hidSystemState)
            let loc = CGEvent(source: nil)?.location ?? .zero
            func click(_ type: CGEventType) {
                guard let e = CGEvent(mouseEventSource: src, mouseType: type,
                                      mouseCursorPosition: loc, mouseButton: cgButton) else { return }
                e.setIntegerValueField(.mouseEventButtonNumber, value: Int64(buttonNumber - 1))
                e.setIntegerValueField(.eventSourceUserData, value: ScrollAnimator.syntheticTag)
                e.post(tap: .cghidEventTap)
            }
            click(.otherMouseDown)
            click(.otherMouseUp)

        case let .scrollOutput(output):
            // Not a one-shot: the engine routes wheel input while the button is held (see
            // HoldScrollGesture). Nothing to post here — reaching this would be a wiring bug.
            switch output { case .volume: break }

        case .autoScroll:
            // Mode toggle, driven by the engine (tap thread, like button triggers): enter/exit
            // Windows-style auto-scroll where moving the pointer scrolls the page.
            EventTapEngine.shared.toggleAutoScroll()

        case .navigateBack:
            SmartNavigation.post(.back)

        case .navigateForward:
            SmartNavigation.post(.forward)
        }
    }

    /// Human-readable name for the UI.
    /// True for hold-and-scroll outputs — the engine treats these mappings specially (the button
    /// enters scroll-output mode on press instead of waiting out the hold duration).
    var isScrollOutput: Bool {
        if case .scrollOutput = self { return true }
        return false
    }

    /// Human-readable name for the UI.
    var displayName: String {
        switch self {
        case .none:
            return Localized.text("action.placeholder")
        case .keyStroke:
            if self == .spaceLeft      { return Localized.text("action.spaceLeft") }
            if self == .spaceRight     { return Localized.text("action.spaceRight") }
            if self == .missionControl { return Localized.text("action.missionControl") }
            if self == .appExpose      { return Localized.text("action.appExpose") }
            guard case let .keyStroke(code, control, option, command, shift) = self else { return "—" }
            var s = ""
            if control { s += "⌃" }
            if option  { s += "⌥" }
            if shift   { s += "⇧" }
            if command { s += "⌘" }
            return s + KeyCodes.name(for: code)
        case let .mediaKey(key):
            return key.name
        case .launchpad:
            return Localized.text("action.launchpad")
        case .spotlight:
            return Localized.text("action.spotlight")
        case .siri:
            return Localized.text("action.siri")
        case .appSwitcher:
            return Localized.text("action.appSwitcher")
        case let .openApp(_, displayName):
            return displayName.isEmpty ? Localized.text("action.openApp") : displayName
        case .smartZoom:
            return Localized.text("action.smartZoom")
        case let .clickButton(buttonNumber):
            if buttonNumber == 3 { return Localized.text("action.clickMiddle") }
            return Localized.format("action.clickButton", buttonNumber)
        case let .scrollOutput(output):
            return output.label
        case .autoScroll:
            return Localized.text("action.autoScroll")
        case .navigateBack:
            return Localized.text("action.navigateBack")
        case .navigateForward:
            return Localized.text("action.navigateForward")
        }
    }
}
