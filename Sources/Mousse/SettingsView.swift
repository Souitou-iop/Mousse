import SwiftUI
import UniformTypeIdentifiers

/// The Settings window (⌘,) with fixed-size preference tabs.
struct SettingsView: View {
    @EnvironmentObject var store: ConfigStore
    @State private var selectedTab: Int
    @ObservedObject private var tracker: DeviceTracker
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var configMessage: String?
    @State private var showingDiagnostics = false
    @State private var scrollEnhancementsExpanded = false

    init(initialTab: Int = 0, tracker: DeviceTracker = .shared) {
        _selectedTab = State(initialValue: initialTab)
        _tracker = ObservedObject(wrappedValue: tracker)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab.tabItem  { Label(Localized.text("tab.general"), systemImage: "gearshape") }.tag(0)
            buttonsTab.tabItem  { Label(Localized.text("tab.buttons"), systemImage: "computermouse") }.tag(1)
            scrollTab.tabItem   { Label(Localized.text("tab.scroll"), systemImage: "scroll") }.tag(2)
            pointerTab.tabItem  { Label(Localized.text("tab.pointer"), systemImage: "cursorarrow.motionlines") }.tag(3)
            DevicesView(tracker: tracker).tabItem { Label(Localized.text("tab.devices"), systemImage: "computermouse.fill") }.tag(5)
            gesturesTab.tabItem { Label(Localized.text("tab.gestures"), systemImage: "hand.draw") }.tag(4)
        }
        .frame(width: 480, height: 480)
        .padding()
        .background(SettingsWindowPatcher(devicesSelected: selectedTab == 5, tracker: tracker))
    }

    private var generalTab: some View {
        Form {
            Picker(Localized.text("general.language"), selection: $store.config.language) {
                ForEach(AppLanguage.allCases, id: \.self) { language in
                    Text(language.label).tag(language)
                }
            }
            Toggle(Localized.text("general.enable"), isOn: Binding(
                get: { store.config.enabled && MoussePermissionGate.isGranted },
                set: { enabled in
                    guard MoussePermissionGate.isGranted else { return }
                    store.config.enabled = enabled
                }))
                .disabled(!MoussePermissionGate.isGranted)
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
            LabeledContent(Localized.text("general.inputMonitoring")) {
                if InputMonitoringPermission.isTrusted {
                    Label(Localized.text("general.granted"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button(Localized.text("general.grant")) {
                        _ = InputMonitoringPermission.request()
                        InputMonitoringPermission.openSettings()
                    }
                }
            }
            LabeledContent(Localized.text("general.version"), value: appVersion)
            if let issue = store.persistenceIssue {
                Section(Localized.text("config.persistenceSection")) {
                    Label(persistenceIssueDescription(issue), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                    HStack {
                        Button(Localized.text("config.retrySave")) { store.retrySave() }
                        if !store.saveIsBlocked {
                            Button(Localized.text("config.dismissIssue")) {
                                store.dismissPersistenceIssue()
                            }
                        }
                    }
                }
            }
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
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    private func persistenceIssueDescription(_ issue: ConfigPersistenceIssue) -> String {
        switch issue {
        case let .loadFailed(message):
            return Localized.format("config.loadFailed", message)
        case let .saveFailed(message):
            return Localized.format("config.saveFailed", message)
        case let .corruptConfigRecovered(backupPath):
            guard let backupPath else { return Localized.text("config.corruptRecoveredNoBackup") }
            return Localized.format("config.corruptRecovered", backupPath)
        }
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
                if store.config.scrollMode.supportsSmoothness {
                    Picker(Localized.text("scroll.smoothness"), selection: $store.config.scrollSmoothness) {
                        ForEach(ScrollSmoothness.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Text(Localized.text("scroll.smoothnessDescription"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if store.config.scrollMode.supportsLinesPerNotch {
                    Stepper(value: $store.config.scrollLines, in: 1...10) {
                        Text(Localized.format("scroll.linesPerNotch", store.config.scrollLines))
                    }
                }
                Text(Localized.text(store.config.scrollMode == .native
                                    ? "scroll.nativeDescription" : "scroll.styleDescription"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            // 速度与方向 — how fast and which way the wheel scrolls.
            Section(Localized.text("scroll.speedSection")) {
                if store.config.scrollMode.supportsWheelSpeed {
                    ScrollSpeedControl(speed: $store.config.scrollSpeed, mode: store.config.scrollMode)
                }
                if store.config.scrollMode.supportsAcceleration {
                    Toggle(Localized.text("scroll.acceleration"), isOn: $store.config.scrollAcceleration)
                }
                Toggle(Localized.text("scroll.reverseVertical"), isOn: $store.config.reverseScroll)
                Toggle(Localized.text("scroll.reverseHorizontal"), isOn: $store.config.reverseScrollHorizontal)
                if store.config.scrollMode.supportsWheelZoom {
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
            }

            // 增强 — extra scrolling inputs (edge resting, the auto-scroll button action, hi-res
            // smoothing).
            Section {
                DisclosureGroup(Localized.text("scroll.enhancementsSection"), isExpanded: $scrollEnhancementsExpanded) {
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
                    if store.config.scrollMode.supportsHighResSmoothing {
                        Toggle(Localized.text("scroll.smoothHighRes"), isOn: $store.config.smoothHighRes)
                        Text(Localized.text("scroll.smoothHighResDescription"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if store.config.scrollMode != .native {
                        Text(Localized.text("scroll.modifierDescription"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            AppExceptionsGroupView()
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
            GameBypassGroupView()
        }
        .formStyle(.grouped)
    }
}

/// The SwiftUI `Settings` scene's window ships with only the close button — no minimize. This
/// patches its style mask the moment the view attaches to the window: adds the minimize traffic
/// light, drops resizability (no zoom button), and tags the window so AppDelegate can watch it.
private struct SettingsWindowPatcher: NSViewRepresentable {
    let devicesSelected: Bool
    let tracker: DeviceTracker
    func makeNSView(context: Context) -> NSView {
        let view = SettingsWindowProbeView(tracker: tracker)
        view.devicesSelected = devicesSelected
        return view
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        (nsView as? SettingsWindowProbeView)?.releaseDemand()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? SettingsWindowProbeView)?.devicesSelected = devicesSelected
        guard let window = nsView.window else { return }
        SettingsWindowConfiguration.apply(to: window)
    }
}

private final class SettingsWindowProbeView: NSView {
    private let tracker: DeviceTracker
    init(tracker: DeviceTracker) { self.tracker = tracker; super.init(frame: .zero) }
    required init?(coder: NSCoder) { return nil }
    var devicesSelected = false { didSet { updateDemand() } }
    private var observers: [NSObjectProtocol] = []
    private var closing = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        guard let window else { tracker.setTabOpen(false); return }
        SettingsWindowConfiguration.apply(to: window)
        for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                     NSWindow.didDeminiaturizeNotification, NSWindow.didBecomeKeyNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window,
                queue: .main) { [weak self] _ in
                    if name == NSWindow.didBecomeKeyNotification { self?.closing = false }
                    self?.updateDemand()
                })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
            object: window, queue: .main) { [weak self] _ in
                self?.closing = true
                self?.tracker.setTabOpen(false)
            })
        for name in [NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil,
                queue: .main) { [weak self] _ in self?.updateDemand() })
        }
        updateDemand()
    }

    func releaseDemand() {
        closing = true
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        tracker.setTabOpen(false)
    }

    private func updateDemand() {
        // The representable updates during SwiftUI rendering; publish tracker state afterwards.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.tracker.setTabOpen(SettingsWindowConfiguration.devicesTabIsVisible(
                selected: self.devicesSelected, windowVisible: self.window?.isVisible ?? false,
                miniaturized: self.window?.isMiniaturized ?? false,
                occlusionVisible: self.window?.occlusionState.contains(.visible) ?? false,
                appHidden: NSApp.isHidden, closing: self.closing))
        }
    }
    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }
}

enum SettingsWindowConfiguration {
    static let identifier = NSUserInterfaceItemIdentifier("com.mousse.settings")

    static func devicesTabIsVisible(selected: Bool, windowVisible: Bool, miniaturized: Bool,
                                    occlusionVisible: Bool, appHidden: Bool, closing: Bool) -> Bool {
        selected && windowVisible && !miniaturized && occlusionVisible && !appHidden && !closing
    }

    static func apply(to window: NSWindow) {
        window.identifier = identifier
        window.styleMask.insert(.miniaturizable)
        window.styleMask.remove(.resizable)
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = true
    }
}
