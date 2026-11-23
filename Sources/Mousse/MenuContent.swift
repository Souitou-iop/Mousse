import SwiftUI

/// The dropdown shown from the menu-bar icon.
struct MenuContent: View {
    @EnvironmentObject var store: ConfigStore
    @ObservedObject private var updates: UpdateChecker
    @Environment(\.openSettings) private var openSettings

    init(updates: UpdateChecker? = nil) {
        _updates = ObservedObject(wrappedValue: updates ?? .shared)
    }

    var body: some View {
        Toggle(Localized.text("menu.enabled"), isOn: Binding(
            get: { store.config.enabled && MoussePermissionGate.isGranted },
            set: { enabled in
                guard MoussePermissionGate.isGranted else { return }
                store.config.enabled = enabled
            }))
        .disabled(!MoussePermissionGate.isGranted)

        Divider()

        Toggle(Localized.text("menu.reverseScroll"), isOn: Binding(
            get: { store.config.reverseScroll && store.config.reverseScrollHorizontal },
            set: { store.config.setLegacyScrollReversal($0) }))
            .disabled(!store.config.enabled || !MoussePermissionGate.isGranted)

        Toggle(Localized.text("menu.smoothScroll"), isOn: Binding(
            get: { store.config.scrollMode.isSmooth },
            set: { isSmooth in
                store.config.scrollMode = ScrollMode.fromSmoothToggle(isSmooth)
            }
        ))
        .disabled(!store.config.enabled || !MoussePermissionGate.isGranted)

        Toggle(Localized.text("menu.pointerAcceleration"), isOn: Binding(
            get: { store.config.pointerAccelerationEnabled },
            // The pointer subsystem only does anything while pointer management is on, so flipping
            // this switch from the menu also engages it — otherwise the toggle would look dead.
            set: { store.config = PointerSettingsResolver.applyMenuAccelerationToggle($0,
                                                                                    to: store.config) }
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

        updateEntry
        Divider()

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

    /// One line that adapts to the checker's state: offer the new version, report the download,
    /// or fall back to a plain check. Never a spinner row plus a second status row — the label
    /// itself carries the state.
    @ViewBuilder
    private var updateEntry: some View {
        if let release = updates.phase.availableRelease {
            switch updates.downloadState {
            case .downloading:
                Button {
                } label: {
                    Label(Localized.text("update.downloading"), systemImage: "arrow.down.circle")
                }
                .disabled(true)
            case .saved:
                Button(Localized.text("update.revealDownload")) {
                    if case .saved(let url) = updates.downloadState {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            case .failed:
                Button(Localized.text("update.retryDownload")) { updates.download(release) }
            case .idle:
                Button(Localized.format("menu.updateAvailable", release.version)) {
                    updates.download(release)
                }
            }
        } else if updates.phase.isChecking {
            Button(Localized.text("update.checking")) {}
                .disabled(true)
        } else {
            Button(Localized.text("menu.checkForUpdates")) {
                Task { await updates.check() }
            }
        }
    }
}
