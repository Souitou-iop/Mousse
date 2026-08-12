import SwiftUI

/// The dropdown shown from the menu-bar icon.
struct MenuContent: View {
    @EnvironmentObject var store: ConfigStore

    var body: some View {
        Toggle(Localized.text("menu.enabled"), isOn: $store.config.enabled)

        Divider()

        if !AccessibilityPermission.isTrusted {
            Button(Localized.text("menu.grantAccessibility")) { AccessibilityPermission.openSettings() }
            Divider()
        }

        SettingsLink { Text(Localized.text("menu.settings")) }
            .keyboardShortcut(",")

        Button(Localized.text("menu.quit")) { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
