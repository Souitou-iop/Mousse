import SwiftUI

/// The dropdown shown from the menu-bar icon.
struct MenuContent: View {
    @EnvironmentObject var store: ConfigStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Toggle(Localized.text("menu.enabled"), isOn: Binding(
            get: { store.config.enabled && MoussePermissionGate.isGranted },
            set: { enabled in
                guard MoussePermissionGate.isGranted else { return }
                store.config.enabled = enabled
            }))
        .disabled(!MoussePermissionGate.isGranted)

        Divider()

        Toggle(Localized.text("menu.reverseScroll"), isOn: $store.config.reverseScroll)
            .disabled(!store.config.enabled || !MoussePermissionGate.isGranted)

        Toggle(Localized.text("menu.smoothScroll"), isOn: Binding(
            get: { store.config.scrollMode != .standard },
            set: { isSmooth in
                store.config.scrollMode = isSmooth ? .smooth : .standard
            }
        ))
        .disabled(!store.config.enabled || !MoussePermissionGate.isGranted)

        Divider()

        if !AccessibilityPermission.isTrusted {
            Button(Localized.text("menu.grantAccessibility")) { AccessibilityPermission.openSettings() }
            Divider()
        }

        if !InputMonitoringPermission.isTrusted {
            Button(Localized.text("menu.grantInputMonitoring")) {
                _ = InputMonitoringPermission.request()
                InputMonitoringPermission.openSettings()
            }
            Divider()
        }

        if store.persistenceIssue != nil {
            Label(Localized.text("menu.configSaveFailed"), systemImage: "exclamationmark.triangle.fill")
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
