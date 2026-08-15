import SwiftUI

/// Mousse — a lean, single-process menu-bar mouse utility for Apple silicon and macOS 15+.
/// Original codebase (not derived from any other app). Pointer control uses a narrowly wrapped
/// IOHID service SPI; the rest of the app uses public macOS APIs.
@main
struct MousseApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = ConfigStore.shared

    var body: some Scene {
        MenuBarExtra("Mousse", systemImage: "computermouse.fill") {
            MenuContent().environmentObject(store)
        }
        Settings {
            SettingsView().environmentObject(store)
        }
    }
}

/// App lifecycle: menu-bar accessory by default; switching to a regular app (Dock icon) only while
/// the Settings window is open — so the window behaves like a normal app window (minimize to Dock,
/// reopen from the Dock icon) without a permanently visible Dock presence. Also ensures
/// Accessibility and brings up the event-tap engine.
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Held for the app's lifetime: exempts the process from App Nap and timer coalescing. A napped
    /// (windowless, "idle-looking") agent gets its run-loop timers coalesced to ~1 s, so after an
    /// idle period the scroll animator's display link can lag a full second behind the first wheel
    /// tick — the wheel input is consumed but nothing moves until the nap lifts. Latency-critical is
    /// the right class for real-time input synthesis; allowing idle system sleep means this never
    /// keeps the Mac awake.
    private var noNapActivity: NSObjectProtocol?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // pure menu-bar app; Dock appears only with Settings
        noNapActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "Real-time mouse input processing")

        if !AccessibilityPermission.isTrusted {
            AccessibilityPermission.request() // shows the system prompt once
        }
        EventTapEngine.shared.start(config: ConfigStore.shared.config)
        PointerSettingsController.shared.start(config: ConfigStore.shared.config)
        // When the Settings window closes, drop the Dock presence again.
        NotificationCenter.default.addObserver(self, selector: #selector(settingsWindowClosed),
                                               name: NSWindow.willCloseNotification, object: nil)
    }

    @objc private func settingsWindowClosed(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.identifier?.rawValue == "com.mousse.settings" else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    /// Clicking the Dock icon reopens the Settings window (this is not a document app and the
    /// window may have been closed or minimized). SwiftUI exposes the Settings scene via the
    /// private `showSettingsWindow:` action; fall back to the pre-Ventura spelling if unavailable.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSApp.setActivationPolicy(.regular) // the window needs a Dock presence to minimize into
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        PointerSettingsController.shared.stopAndRestore()
        // The config write is debounced; a change made in the last half second is still in flight.
        ConfigStore.shared.flushPendingSave()
    }
}
