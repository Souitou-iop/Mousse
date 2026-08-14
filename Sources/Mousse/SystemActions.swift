import AppKit
import CoreGraphics
import Foundation

/// Drives WindowServer/Dock features that ignore synthetic key events on recent macOS.
///
/// Two private mechanisms, both resolved at runtime via `dlsym` (no link-time dependency):
///   • `CoreDockSendNotification` — Mission Control / Exposé / Show Desktop (Dock SPI).
///   • CoreGraphics Symbolic-HotKey (SHK) API — switching Spaces.
///
/// Switching Spaces: we READ which key the user has bound to the Space-switch hotkey (read-only) and
/// synthesize exactly that key, so it works even if they remapped it. If the binding can't be read at
/// all, we fall back to the macOS default (Ctrl+←/→); if it reads as disabled we skip instead (see
/// `postSHK`). We deliberately NEVER write the SHK configuration — this only ever adds mouse-driven
/// input, it does not modify any system setting.
enum SystemActions {

    // MARK: - Dock notifications (Mission Control / Exposé / Show Desktop)

    private typealias SendFn = @convention(c) (CFString, Int32) -> Void

    private static let send: SendFn? = {
        // RTLD_DEFAULT (-2): search every already-loaded image for the symbol.
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CoreDockSendNotification")
        else { return nil }
        return unsafeBitCast(sym, to: SendFn.self)
    }()

    static var isAvailable: Bool { send != nil }

    /// Toggle Mission Control (overview of all windows/spaces).
    static func missionControl() { fire("com.apple.expose.awake") }
    /// Toggle App Exposé (windows of the front app).
    static func appExpose() { fire("com.apple.expose.front.awake") }
    /// Toggle Show Desktop.
    static func showDesktop() { fire("com.apple.showdesktop.awake") }

    private static func fire(_ name: String) {
        DispatchQueue.main.async { send?(name as CFString, 0) }
    }

    // MARK: - Symbolic hotkeys (switch Spaces)

    /// Switch to the Space on the left / right.
    static func spaceLeft()  { postSHK(shkSpaceLeft,  defaultVKC: 0x7B) } // ← left arrow
    static func spaceRight() { postSHK(shkSpaceRight, defaultVKC: 0x7C) } // → right arrow

    private static let shkSpaceLeft:  Int32 = 79
    private static let shkSpaceRight: Int32 = 81

    // MARK: - Launchpad / Apps

    /// Toggle Launchpad.
    ///
    /// macOS 26+ replaced Launchpad.app with the "Apps" app: open it directly — ZERO system
    /// writes, no SHK binding is ever touched. (Trade-off: "open" is not a toggle — pressing the
    /// button again won't close the grid, Esc does.)
    ///
    /// macOS 15 and earlier keep a real Launchpad SHK (usually bound to F4): replay the user's
    /// binding when there is one (the normal case — no writes). Only when the user disabled the
    /// shortcut does the MMF-style fallback engage: force-enable the SHK with a keyboard-
    /// unreachable binding (fn|numpad on a virtual key code far above any real key) and replay
    /// that. The user's shortcuts and keyboard layout are never changed.
    static func launchpad() {
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 {
            let appsURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.apps.launcher")
                ?? (FileManager.default.fileExists(atPath: "/System/Applications/Apps.app")
                    ? URL(fileURLWithPath: "/System/Applications/Apps.app") : nil)
            if let apps = appsURL {
                DispatchQueue.main.async {
                    NSWorkspace.shared.openApplication(at: apps, configuration: NSWorkspace.OpenConfiguration())
                }
                return
            }
            // Apps.app unexpectedly absent (pre-release builds) — fall through to the SHK path.
        }
        launchpadViaSHK()
    }

    private static func launchpadViaSHK() {
        queue.async {
            var keq: UInt16 = 0, vkc: UInt16 = 0, mods: UInt32 = 0
            let readable = getSHK?(shkLaunchpad, &keq, &vkc, &mods) == 0
            let usable = readable && (isEnabled?(shkLaunchpad) ?? false)
                && vkc != kNullKeyEquivalent && vkc != 0
            let targetVKC: UInt16, targetMods: UInt32
            if usable {
                (targetVKC, targetMods) = (vkc, mods)
            } else {
                _ = setSHKEnabled?(shkLaunchpad, true)
                _ = setSHKValue?(shkLaunchpad, kNullKeyEquivalent,
                                 outOfReachBase + UInt16(shkLaunchpad),
                                 kCGSNumericPadKeyMask | kCGSFunctionKeyMask)
                (targetVKC, targetMods) = (outOfReachBase + UInt16(shkLaunchpad),
                                           kCGSNumericPadKeyMask | kCGSFunctionKeyMask)
            }
            // Post regardless of the SHK write result — a failed write might still work (MMF does
            // the same), and on the off chance nothing resolves, a bare F4 is the usual default.
            postKey(targetVKC, targetMods)
        }
    }

    private static let shkLaunchpad: Int32 = 160
    private static let outOfReachBase: UInt16 = 400 // far above any real keyboard key
    private static let kCGSNumericPadKeyMask: UInt32 = 1 << 21
    private static let kCGSFunctionKeyMask: UInt32 = 1 << 23

    private typealias SetSHKValueFn = @convention(c) (Int32, UInt16, UInt16, UInt32) -> Int32
    private typealias SetSHKEnabledFn = @convention(c) (Int32, Bool) -> Int32
    private static let setSHKValue = lookup("CGSSetSymbolicHotKeyValue", as: SetSHKValueFn.self)
    private static let setSHKEnabled = lookup("CGSSetSymbolicHotKeyEnabled", as: SetSHKEnabledFn.self)

    private static let kNullKeyEquivalent: UInt16 = 0xFFFF
    private static let kControlMask: UInt32 = 1 << 18 // kCGSControlKeyMask == CGEventFlags.maskControl

    // Runs SHK reads and the synthesized key off the event-tap thread.
    private static let queue = DispatchQueue(label: "com.mousse.shk", qos: .userInteractive)

    private typealias GetSHKFn    = @convention(c) (Int32, UnsafeMutablePointer<UInt16>, UnsafeMutablePointer<UInt16>, UnsafeMutablePointer<UInt32>) -> Int32
    private typealias IsEnabledFn = @convention(c) (Int32) -> Bool

    private static func lookup<T>(_ name: String, as: T.Type) -> T? {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }
    private static let getSHK    = lookup("CGSGetSymbolicHotKeyValue", as: GetSHKFn.self)
    private static let isEnabled = lookup("CGSIsSymbolicHotKeyEnabled", as: IsEnabledFn.self)

    /// Trigger a Space-switch hotkey by synthesizing the key it's bound to (read-only lookup).
    /// If the binding can't be READ (SPI unavailable), assume the macOS default Ctrl+arrow. But if
    /// it reads as disabled or bound to a character key we can't replay, do NOTHING: WindowServer
    /// wouldn't consume the keystroke, so posting one would type a real Ctrl+arrow into the focused
    /// app (caret jumps in editors). Never writes any system configuration.
    private static func postSHK(_ shk: Int32, defaultVKC: UInt16) {
        queue.async {
            var keq: UInt16 = 0, vkc: UInt16 = 0, mods: UInt32 = 0
            guard let getSHK, let isEnabled, getSHK(shk, &keq, &vkc, &mods) == 0 else {
                postKey(defaultVKC, kControlMask) // binding unreadable — assume the default
                return
            }
            guard isEnabled(shk), keq == kNullKeyEquivalent, vkc != kNullKeyEquivalent else {
                logSkippedSHK()
                return
            }
            // The hotkey resolves by virtual key code — replay exactly what the user has bound.
            postKey(vkc, mods)
        }
    }

    private static var loggedSkippedSHK = false // touched only on `queue`
    private static func logSkippedSHK() {
        guard !loggedSkippedSHK else { return }
        loggedSkippedSHK = true
        NSLog("Mousse: skipping Space switch — the \"Move left/right a space\" shortcut is disabled "
            + "or bound to a character key (enable it in System Settings > Keyboard > Shortcuts > "
            + "Mission Control)")
    }

    private static func postKey(_ vkc: UInt16, _ mods: UInt32) {
        let src = CGEventSource(stateID: .privateState)
        let loc = CGEventTapLocation.cgSessionEventTap // SHKs are observed at the session tap
        let flags = CGEventFlags(rawValue: UInt64(mods))
        if let down = CGEvent(keyboardEventSource: src, virtualKey: vkc, keyDown: true) {
            down.flags = flags; down.post(tap: loc)
        }
        if let up = CGEvent(keyboardEventSource: src, virtualKey: vkc, keyDown: false) {
            up.flags = flags; up.post(tap: loc)
        }
    }
}
