import SwiftUI
import UniformTypeIdentifiers

/// The Settings window (⌘,) with five fixed-size preference tabs.
struct SettingsView: View {
    @EnvironmentObject var store: ConfigStore
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var configMessage: String?
    @State private var showingDiagnostics = false

    var body: some View {
        TabView {
            generalTab.tabItem  { Label(Localized.text("tab.general"), systemImage: "gearshape") }
            buttonsTab.tabItem  { Label(Localized.text("tab.buttons"), systemImage: "computermouse") }
            scrollTab.tabItem   { Label(Localized.text("tab.scroll"), systemImage: "scroll") }
            pointerTab.tabItem  { Label(Localized.text("tab.pointer"), systemImage: "cursorarrow.motionlines") }
            gesturesTab.tabItem { Label(Localized.text("tab.gestures"), systemImage: "hand.draw") }
        }
        .frame(width: 480, height: 480)
        .padding()
        .background(SettingsWindowPatcher())
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
            Section(Localized.text("diagnostics.section")) {
                LabeledContent(Localized.text("diagnostics.status")) {
                    DiagnosticsSummaryView()
                }
                Button(Localized.text("diagnostics.open")) { showingDiagnostics = true }
            }
            Section(Localized.text("general.configSection")) {
                Button(Localized.text("general.exportConfig")) { exportConfig() }
                Button(Localized.text("general.importConfig")) { importConfig() }
                Text(Localized.text("general.configDescription"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .alert("Mousse", isPresented: Binding(
            get: { configMessage != nil },
            set: { if !$0 { configMessage = nil } }
        )) {
            Button(Localized.text("common.ok"), role: .cancel) {}
        } message: {
            Text(configMessage ?? "")
        }
        .sheet(isPresented: $showingDiagnostics) {
            DiagnosticsView()
                .environmentObject(store)
        }
    }

    private func exportConfig() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Mousse-config-\(configTimestamp()).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ConfigTransfer.export(store.config, to: url)
            configMessage = Localized.text("config.exportSuccess")
        } catch {
            configMessage = Localized.format("config.exportFailed", error.localizedDescription)
        }
    }

    private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            store.config = try ConfigTransfer.importConfig(from: url)
            configMessage = Localized.text("config.importSuccess")
        } catch {
            configMessage = Localized.format("config.importFailed", error.localizedDescription)
        }
    }

    private func configTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.18.1"
    }

    private var buttonsTab: some View {
        ButtonMappingsView()
    }

    private var scrollTab: some View {
        Form {
            // 滚动样式 — which engine drives the wheel.
            Section(Localized.text("scroll.styleSection")) {
                Picker(Localized.text("scroll.style"), selection: $store.config.scrollMode) {
                    ForEach(ScrollMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                if store.config.scrollMode == .smooth {
                    Picker(Localized.text("scroll.smoothness"), selection: $store.config.scrollSmoothness) {
                        ForEach(ScrollSmoothness.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Text(Localized.text("scroll.smoothnessDescription"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if store.config.scrollMode == .smoothStep {
                    Stepper(value: $store.config.scrollLines, in: 1...10) {
                        Text(Localized.format("scroll.linesPerNotch", store.config.scrollLines))
                    }
                }
                Text(Localized.text("scroll.styleDescription"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            // 速度与方向 — how fast and which way the wheel scrolls.
            Section(Localized.text("scroll.speedSection")) {
                if store.config.scrollMode == .smooth {
                    VStack(alignment: .leading) {
                        Text(Localized.format("scroll.speedValue", store.config.scrollSpeed))
                        // Floor of 0.05 (not 0.2): high-res "continuous" mice natively scroll fast,
                        // and their gain is speed/0.5 — a 0.2 floor still meant 40% of native, too
                        // fast for slow scrollers. 0.05 → 10% of native. Finer step at the low end.
                        Slider(value: $store.config.scrollSpeed, in: 0.05...3.0, step: 0.05) {
                            Text(Localized.text("scroll.speed"))
                        } minimumValueLabel: { Text(Localized.text("scroll.slow")).font(.caption) }
                          maximumValueLabel: { Text(Localized.text("scroll.fast")).font(.caption) }
                    }
                    Toggle(Localized.text("scroll.acceleration"), isOn: $store.config.scrollAcceleration)
                }
                Toggle(Localized.text("scroll.reverse"), isOn: $store.config.reverseScroll)
                VStack(alignment: .leading) {
                    Text(Localized.format("scroll.zoomSpeedValue", store.config.zoomSpeed))
                    // Cmd+wheel pinch-zoom sensitivity — independent of the scroll-speed slider so
                    // a fast scroll feel doesn't force an aggressive zoom.
                    Slider(value: $store.config.zoomSpeed, in: 0.2...6.0, step: 0.1) {
                        Text(Localized.text("scroll.zoomSpeed"))
                    } minimumValueLabel: { Text(Localized.text("scroll.slow")).font(.caption) }
                      maximumValueLabel: { Text(Localized.text("scroll.fast")).font(.caption) }
                }
            }

            // 增强 — extra scrolling inputs (edge resting, the auto-scroll button action, hi-res
            // smoothing).
            Section(Localized.text("scroll.enhancementsSection")) {
                Toggle(Localized.text("scroll.edgeScroll"), isOn: $store.config.edgeScroll)
                if store.config.edgeScroll {
                    VStack(alignment: .leading) {
                        Text(Localized.format("scroll.edgeScrollSpeedValue", Int(store.config.edgeScrollSpeed)))
                        Slider(value: $store.config.edgeScrollSpeed, in: 50...2400, step: 50) {
                            Text(Localized.text("scroll.edgeScrollSpeed"))
                        } minimumValueLabel: { Text(Localized.text("scroll.slow")).font(.caption) }
                          maximumValueLabel: { Text(Localized.text("scroll.fast")).font(.caption) }
                    }
                    Text(Localized.text("scroll.edgeScrollDescription"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading) {
                    Text(Localized.format("scroll.autoScrollBaseSpeedValue",
                                          Int(store.config.autoScrollBaseSpeed)))
                    Slider(value: $store.config.autoScrollBaseSpeed, in: 0...1000, step: 10) {
                        Text(Localized.text("scroll.autoScrollBaseSpeed"))
                    } minimumValueLabel: { Text(Localized.text("scroll.slow")).font(.caption) }
                      maximumValueLabel: { Text(Localized.text("scroll.fast")).font(.caption) }
                }
                VStack(alignment: .leading) {
                    Text(Localized.format("scroll.autoScrollSpeedValue", store.config.autoScrollSpeed))
                    Slider(value: $store.config.autoScrollSpeed,
                           in: AutoScrollSpeedSetting.range,
                           step: AutoScrollSpeedSetting.step) {
                        Text(Localized.text("scroll.autoScrollSpeed"))
                    } minimumValueLabel: { Text(Localized.text("scroll.slow")).font(.caption) }
                      maximumValueLabel: { Text(Localized.text("scroll.fast")).font(.caption) }
                }
                Text(Localized.text("scroll.autoScrollSpeedDescription"))
                    .font(.caption).foregroundStyle(.secondary)
                Stepper(value: $store.config.autoScrollClickDelay,
                        in: AutoScrollClickDelaySetting.range,
                        step: AutoScrollClickDelaySetting.step) {
                    Text(Localized.format(
                        "scroll.autoScrollClickDelayValue",
                        Int((store.config.autoScrollClickDelay * 1000).rounded())))
                }
                Text(Localized.text("scroll.autoScrollClickDelayDescription"))
                    .font(.caption).foregroundStyle(.secondary)
                Toggle(Localized.text("scroll.showAutoScrollHUD"),
                       isOn: $store.config.showAutoScrollHUD)
                if store.config.scrollMode != .standard {
                    Toggle(Localized.text("scroll.smoothHighRes"), isOn: $store.config.smoothHighRes)
                    Text(Localized.text("scroll.smoothHighResDescription"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section(Localized.text("scroll.modifiers")) {
                Text(Localized.text("scroll.modifierDescription"))
                    .font(.caption)
            }
            ExcludedAppsView()
            TransposedAppsView() // axis-swap works in every scroll mode, including Standard
        }
        .formStyle(.grouped)
    }

    private var pointerTab: some View {
        PointerSettingsView()
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
    }
}

/// The SwiftUI `Settings` scene's window ships with only the close button — no minimize. This
/// patches its style mask the moment the view attaches to the window: adds the minimize traffic
/// light, drops resizability (no zoom button), and tags the window so AppDelegate can watch it.
private struct SettingsWindowPatcher: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        SettingsWindowProbeView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        SettingsWindowConfiguration.apply(to: window)
    }
}

private final class SettingsWindowProbeView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        SettingsWindowConfiguration.apply(to: window)
    }
}

enum SettingsWindowConfiguration {
    static let identifier = NSUserInterfaceItemIdentifier("com.mousse.settings")

    static func apply(to window: NSWindow) {
        window.identifier = identifier
        window.styleMask.insert(.miniaturizable)
        window.styleMask.remove(.resizable)
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = true
    }
}
