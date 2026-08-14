import SwiftUI

/// The Settings window (⌘,). Three tabs: General, Buttons, Scroll.
struct SettingsView: View {
    @EnvironmentObject var store: ConfigStore
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        TabView {
            generalTab.tabItem  { Label(Localized.text("tab.general"), systemImage: "gearshape") }
            buttonsTab.tabItem  { Label(Localized.text("tab.buttons"), systemImage: "computermouse") }
            scrollTab.tabItem   { Label(Localized.text("tab.scroll"), systemImage: "scroll") }
            gesturesTab.tabItem { Label(Localized.text("tab.gestures"), systemImage: "hand.draw") }
        }
        .frame(width: 480, height: 360)
        .padding()
    }

    private var generalTab: some View {
        Form {
            Picker(Localized.text("general.language"), selection: $store.config.language) {
                ForEach(AppLanguage.allCases, id: \.self) { language in
                    Text(language.label).tag(language)
                }
            }
            Toggle(Localized.text("general.enable"), isOn: $store.config.enabled)
            Toggle(Localized.text("general.launchAtLogin"), isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    LoginItem.setEnabled(newValue)
                    launchAtLogin = LoginItem.isEnabled // resync to the real status
                }
            LabeledContent(Localized.text("general.accessibility")) {
                if AccessibilityPermission.isTrusted {
                    Label(Localized.text("general.granted"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Button(Localized.text("general.grant")) { AccessibilityPermission.openSettings() }
                }
            }
            LabeledContent(Localized.text("general.version"), value: appVersion)
        }
        .formStyle(.grouped)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.9.4"
    }

    private var buttonsTab: some View {
        ButtonMappingsView()
    }

    private var scrollTab: some View {
        Form {
            Picker(Localized.text("scroll.style"), selection: $store.config.scrollMode) {
                ForEach(ScrollMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            if store.config.scrollMode == .smooth {
                Picker(Localized.text("scroll.smoothness"), selection: $store.config.scrollSmoothness) {
                    ForEach(ScrollSmoothness.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Text(Localized.text("scroll.smoothnessDescription"))
                    .font(.caption).foregroundStyle(.secondary)
                VStack(alignment: .leading) {
                    Text(Localized.format("scroll.speedValue", store.config.scrollSpeed))
                    // Floor of 0.05 (not 0.2): high-res "continuous" mice natively scroll fast, and
                    // their gain is speed/0.5 — a 0.2 floor still meant 40% of native, too fast for
                    // slow scrollers. 0.05 → 10% of native. Finer step for control at the low end.
                    Slider(value: $store.config.scrollSpeed, in: 0.05...1.5, step: 0.05) {
                        Text(Localized.text("scroll.speed"))
                    } minimumValueLabel: { Text(Localized.text("scroll.slow")).font(.caption) }
                      maximumValueLabel: { Text(Localized.text("scroll.fast")).font(.caption) }
                }
                Toggle(Localized.text("scroll.acceleration"), isOn: $store.config.scrollAcceleration)
            }
            if store.config.scrollMode == .smoothStep {
                Stepper(value: $store.config.scrollLines, in: 1...10) {
                    Text(Localized.format("scroll.linesPerNotch", store.config.scrollLines))
                }
            }
            Toggle(Localized.text("scroll.reverse"), isOn: $store.config.reverseScroll)
            VStack(alignment: .leading) {
                Text(Localized.format("scroll.zoomSpeedValue", store.config.zoomSpeed))
                // Cmd+wheel pinch-zoom sensitivity — independent of the scroll-speed slider so a
                // fast scroll feel doesn't force an aggressive zoom.
                Slider(value: $store.config.zoomSpeed, in: 0.5...3.0, step: 0.1) {
                    Text(Localized.text("scroll.zoomSpeed"))
                } minimumValueLabel: { Text(Localized.text("scroll.slow")).font(.caption) }
                  maximumValueLabel: { Text(Localized.text("scroll.fast")).font(.caption) }
            }
            Toggle(Localized.text("scroll.edgeScroll"), isOn: $store.config.edgeScroll)
            if store.config.edgeScroll {
                VStack(alignment: .leading) {
                    Text(Localized.format("scroll.edgeScrollSpeedValue", Int(store.config.edgeScrollSpeed)))
                    Slider(value: $store.config.edgeScrollSpeed, in: 100...1200, step: 50) {
                        Text(Localized.text("scroll.edgeScrollSpeed"))
                    } minimumValueLabel: { Text(Localized.text("scroll.slow")).font(.caption) }
                      maximumValueLabel: { Text(Localized.text("scroll.fast")).font(.caption) }
                }
                Text(Localized.text("scroll.edgeScrollDescription"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if store.config.scrollMode != .standard {
                Toggle(Localized.text("scroll.smoothHighRes"), isOn: $store.config.smoothHighRes)
                Text(Localized.text("scroll.smoothHighResDescription"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(Localized.text("scroll.styleDescription"))
                .font(.caption).foregroundStyle(.secondary)
            Section(Localized.text("scroll.modifiers")) {
                Text(Localized.text("scroll.modifierDescription"))
                    .font(.caption)
            }
            if store.config.scrollMode != .standard {
                ExcludedAppsView()
            }
            TransposedAppsView() // axis-swap works in every scroll mode, including Standard
        }
        .formStyle(.grouped)
    }

    private var gesturesTab: some View {
        Form {
            Picker(Localized.text("gestures.spaceDrag"), selection: $store.config.spaceDragButton) {
                Text(Localized.text("common.off")).tag(0)
                ForEach(3...9, id: \.self) { Text(Localized.format("common.button", $0)).tag($0) }
            }
            if store.config.spaceDragButton != 0 {
                Toggle(Localized.text("gestures.followFinger"), isOn: $store.config.spaceDragFollowFinger)
                if !store.config.spaceDragFollowFinger {
                    VStack(alignment: .leading) {
                        Text(Localized.format("gestures.dragDistance", Int(store.config.spaceDragThreshold)))
                        Slider(value: $store.config.spaceDragThreshold, in: 100...400, step: 10)
                    }
                }
                Toggle(Localized.text("gestures.reverse"), isOn: $store.config.spaceDragReverse)
                Toggle(Localized.text("gestures.lockPointer"), isOn: $store.config.spaceDragLockPointer)
                Text(Localized.text("gestures.lockPointerDescription"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(Localized.text("gestures.description"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .background(SettingsWindowPatcher())
    }
}

/// The SwiftUI `Settings` scene's window ships with only the close button — no minimize. This
/// patches its style mask the moment the view attaches to the window: adds the minimize traffic
/// light, drops resizability (no zoom button), and tags the window so AppDelegate can watch it.
private struct SettingsWindowPatcher: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.identifier = NSUserInterfaceItemIdentifier("com.mousse.settings")
            window.styleMask.insert(.miniaturizable)
            window.styleMask.remove(.resizable)
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
