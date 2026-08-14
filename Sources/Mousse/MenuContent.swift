import SwiftUI

/// The dropdown shown from the menu-bar icon.
struct MenuContent: View {
    @EnvironmentObject var store: ConfigStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Toggle(Localized.text("menu.enabled"), isOn: $store.config.enabled)

        Divider()

        if !AccessibilityPermission.isTrusted {
            Button(Localized.text("menu.grantAccessibility")) { AccessibilityPermission.openSettings() }
            Divider()
        }

        Button(Localized.text("menu.settings")) {
            // Dock presence while the Settings window is open (minimize/reopen needs it); the
            // window closing drops it again (see AppDelegate.settingsWindowClosed).
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
            .keyboardShortcut(",")

        Button(Localized.text("menu.quit")) { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
