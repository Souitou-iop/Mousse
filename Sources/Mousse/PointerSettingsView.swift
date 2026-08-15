import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PointerSettingsView: View {
    @EnvironmentObject private var store: ConfigStore
    @ObservedObject private var controller = PointerSettingsController.shared
    @State private var editingID: UUID?

    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        if let editingID,
           let index = store.config.pointerAppProfiles.firstIndex(where: { $0.id == editingID }) {
            PointerAppProfileEditor(
                profile: $store.config.pointerAppProfiles[index],
                globalSpeed: store.config.pointerSpeedMultiplier,
                onBack: { self.editingID = nil })
        } else {
            overview
                .onReceive(timer) { _ in
                    _ = controller.diagnosticsSnapshot(refreshActual: true)
                }
        }
    }

    private var overview: some View {
        Form {
            Section(Localized.text("pointer.globalSection")) {
                Toggle(Localized.text("pointer.manage"),
                       isOn: $store.config.pointerControlEnabled)
                Text(Localized.text("pointer.manageDescription"))
                    .font(.caption).foregroundStyle(.secondary)
                Group {
                    Toggle(Localized.text("pointer.acceleration"),
                           isOn: $store.config.pointerAccelerationEnabled)
                    VStack(alignment: .leading) {
                        Text(Localized.format(
                            "pointer.speedValue", store.config.pointerSpeedMultiplier))
                        Slider(value: $store.config.pointerSpeedMultiplier,
                               in: PointerSpeedSetting.range,
                               step: PointerSpeedSetting.step) {
                            Text(Localized.text("pointer.speed"))
                        } minimumValueLabel: {
                            Text(Localized.text("scroll.slow")).font(.caption)
                        } maximumValueLabel: {
                            Text(Localized.text("scroll.fast")).font(.caption)
                        }
                    }
                    Text(Localized.text("pointer.dpiDescription"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .disabled(!store.config.pointerControlEnabled)
            }

            statusSection

            Section(Localized.text("pointer.appSection")) {
                if store.config.pointerAppProfiles.isEmpty {
                    Text(Localized.text("pointer.noApps"))
                        .foregroundStyle(.secondary)
                }
                ForEach($store.config.pointerAppProfiles) { $profile in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            AppRow(bundleID: profile.bundleID)
                            Text(profileSummary(profile))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button(Localized.text("apps.edit")) { editingID = profile.id }
                        Button(Localized.text("common.delete"), role: .destructive) {
                            remove(profile)
                        }
                    }
                }
                Button(Localized.text("pointer.addApp"), action: addApp)
                Text(Localized.text("pointer.appDescription"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .disabled(!store.config.pointerControlEnabled)
        }
        .formStyle(.grouped)
    }

    private var statusSection: some View {
        Section(Localized.text("pointer.statusSection")) {
            LabeledContent(Localized.text("pointer.frontmostApp")) {
                if let bundleID = controller.snapshot.frontmostBundleID {
                    AppRow(bundleID: bundleID)
                } else {
                    Text(Localized.text("diagnostics.notDetected"))
                        .foregroundStyle(.secondary)
                }
            }
            LabeledContent(
                Localized.text("pointer.matchedProfile"),
                value: matchedProfileDescription)
            LabeledContent(
                Localized.text("pointer.appliedAcceleration"),
                value: accelerationDescription)
            LabeledContent(
                Localized.text("pointer.appliedSpeed"),
                value: speedDescription)
            LabeledContent(
                Localized.text("pointer.appliedDevices"),
                value: Localized.format(
                    "pointer.appliedDevicesValue",
                    controller.snapshot.appliedDeviceCount,
                    controller.snapshot.connectedDeviceCount))
            LabeledContent(Localized.text("pointer.health")) {
                Label(healthDescription, systemImage: healthIcon)
                    .foregroundStyle(healthColor)
            }
            if controller.snapshot.health == .drifted {
                Button(Localized.text("pointer.adoptSystemSettings")) {
                    controller.adoptCurrentSystemSettings()
                }
                Text(Localized.text("pointer.adoptSystemSettingsDescription"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var matchedProfileDescription: String {
        guard controller.snapshot.managementEnabled else {
            return Localized.text("pointer.systemUnchanged")
        }
        guard let bundleID = controller.snapshot.matchedProfileBundleID else {
            return Localized.text("pointer.globalProfile")
        }
        let name = InstalledApp.lookup(bundleID)?.name ?? bundleID
        return Localized.format("pointer.appProfile", name)
    }

    private var accelerationDescription: String {
        guard let enabled = controller.snapshot.actualAccelerationEnabled else {
            return Localized.text("pointer.systemUnchanged")
        }
        return enabled
            ? Localized.text("pointer.override.enabled")
            : Localized.text("pointer.override.disabled")
    }

    private var speedDescription: String {
        guard let speed = controller.snapshot.actualSpeedMultiplier else {
            return Localized.text("pointer.systemUnchanged")
        }
        return Localized.format("pointer.speedValue", speed)
    }

    private var healthDescription: String {
        switch controller.snapshot.health {
        case .inactive: return Localized.text("pointer.health.inactive")
        case .applied: return Localized.text("pointer.health.applied")
        case .unavailable: return Localized.text("pointer.health.unavailable")
        case .failed: return Localized.text("pointer.health.failed")
        case .drifted: return Localized.text("pointer.health.drifted")
        }
    }

    private var healthIcon: String {
        switch controller.snapshot.health {
        case .inactive: return "pause.circle"
        case .applied: return "checkmark.circle.fill"
        case .unavailable: return "questionmark.circle"
        case .failed: return "exclamationmark.triangle.fill"
        case .drifted: return "arrow.triangle.2.circlepath"
        }
    }

    private var healthColor: Color {
        switch controller.snapshot.health {
        case .inactive, .unavailable: return .secondary
        case .applied: return .green
        case .failed, .drifted: return .orange
        }
    }

    private func profileSummary(_ profile: PointerAppProfile) -> String {
        let acceleration = profile.acceleration.label
        let speed = profile.speedMultiplier.map {
            Localized.format("pointer.speedValue", $0)
        } ?? Localized.text("pointer.useGlobalSpeed")
        return "\(acceleration) · \(speed)"
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = Localized.text("pointer.addApp")
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier,
              !store.config.pointerAppProfiles.contains(where: { $0.bundleID == bundleID })
        else { return }
        let profile = PointerAppProfile(bundleID: bundleID)
        store.config.pointerAppProfiles.append(profile)
        editingID = profile.id
    }

    private func remove(_ profile: PointerAppProfile) {
        store.config.pointerAppProfiles.removeAll { $0.id == profile.id }
    }
}

private struct PointerAppProfileEditor: View {
    @Binding var profile: PointerAppProfile
    let globalSpeed: Double
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: onBack) {
                    Label(Localized.text("common.back"), systemImage: "chevron.left")
                }
                Spacer()
                AppRow(bundleID: profile.bundleID)
            }
            .padding(.bottom, 4)

            Form {
                Section(Localized.text("pointer.appSettingsSection")) {
                    Picker(Localized.text("pointer.acceleration"), selection: $profile.acceleration) {
                        ForEach(PointerAccelerationOverride.allCases, id: \.self) { value in
                            Text(value.label).tag(value)
                        }
                    }
                    Toggle(Localized.text("pointer.useGlobalSpeed"), isOn: usesGlobalSpeed)
                    if profile.speedMultiplier != nil {
                        VStack(alignment: .leading) {
                            Text(Localized.format(
                                "pointer.speedValue", profile.speedMultiplier ?? globalSpeed))
                            Slider(value: speedMultiplier,
                                   in: PointerSpeedSetting.range,
                                   step: PointerSpeedSetting.step) {
                                Text(Localized.text("pointer.speed"))
                            } minimumValueLabel: {
                                Text(Localized.text("scroll.slow")).font(.caption)
                            } maximumValueLabel: {
                                Text(Localized.text("scroll.fast")).font(.caption)
                            }
                        }
                    }
                    Text(Localized.text("pointer.appEditorDescription"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .padding()
    }

    private var usesGlobalSpeed: Binding<Bool> {
        Binding(
            get: { profile.speedMultiplier == nil },
            set: { useGlobal in
                profile.speedMultiplier = useGlobal ? nil : globalSpeed
            })
    }

    private var speedMultiplier: Binding<Double> {
        Binding(
            get: { profile.speedMultiplier ?? globalSpeed },
            set: { profile.speedMultiplier = PointerSpeedSetting.clamp($0) })
    }
}

extension PointerAccelerationOverride {
    var label: String {
        switch self {
        case .inherit: return Localized.text("pointer.override.inherit")
        case .enabled: return Localized.text("pointer.override.enabled")
        case .disabled: return Localized.text("pointer.override.disabled")
        }
    }
}

extension PointerFailureReason {
    var localizedDescription: String {
        switch self {
        case .serviceUnavailable: return Localized.text("pointer.failure.serviceUnavailable")
        case .noMouse: return Localized.text("pointer.failure.noMouse")
        case .baselineReadFailed: return Localized.text("pointer.failure.baselineReadFailed")
        case .writeFailed: return Localized.text("pointer.failure.writeFailed")
        case .restoreFailed: return Localized.text("pointer.failure.restoreFailed")
        case .externalChange: return Localized.text("pointer.failure.externalChange")
        }
    }
}
