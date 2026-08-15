import AppKit
import SwiftUI

@MainActor
private final class DiagnosticsViewModel: ObservableObject {
    @Published var snapshot = EventTapEngine.shared.diagnosticsSnapshot()
    @Published var pointerSnapshot = PointerDiagnosticsSnapshot.inactive

    private let cursorApp = CursorAppResolver()

    func refresh() {
        let pointerBundleID: String?
        if let location = CGEvent(source: nil)?.location {
            pointerBundleID = cursorApp.bundleID(at: location)
        } else {
            pointerBundleID = nil
        }
        snapshot = EventTapEngine.shared.diagnosticsSnapshot(pointerBundleID: pointerBundleID)
        pointerSnapshot = PointerSettingsController.shared
            .diagnosticsSnapshot(refreshActual: true)
    }
}

struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = DiagnosticsViewModel()

    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(Localized.text("diagnostics.title"))
                    .font(.title3.weight(.semibold))
                Spacer()
                Button(action: dismiss.callAsFunction) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(Localized.text("diagnostics.close"))
            }
            .padding([.horizontal, .top])

            Form {
                systemSection
                pointerSection
                contextSection
                mouseSection
            }
            .formStyle(.grouped)
        }
        .frame(width: 540, height: 500)
        .onAppear { model.refresh() }
        .onReceive(timer) { _ in model.refresh() }
    }

    private var pointerSection: some View {
        Section(Localized.text("diagnostics.pointerSection")) {
            DiagnosticRow(
                label: Localized.text("pointer.manage"),
                value: model.pointerSnapshot.managementEnabled
                    ? Localized.text("diagnostics.enabled")
                    : Localized.text("diagnostics.disabled"),
                systemImage: model.pointerSnapshot.managementEnabled
                    ? "cursorarrow.motionlines" : "cursorarrow",
                color: model.pointerSnapshot.managementEnabled ? .green : .secondary)
            LabeledContent(Localized.text("pointer.matchedProfile")) {
                Text(pointerProfileDescription)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            LabeledContent(Localized.text("pointer.targetAcceleration")) {
                Text(pointerTargetAccelerationDescription)
                    .foregroundStyle(.secondary)
            }
            LabeledContent(Localized.text("pointer.targetSpeed")) {
                Text(pointerTargetSpeedDescription)
                    .foregroundStyle(.secondary)
            }
            LabeledContent(Localized.text("pointer.appliedAcceleration")) {
                Text(pointerAccelerationDescription)
                    .foregroundStyle(.secondary)
            }
            LabeledContent(Localized.text("pointer.appliedSpeed")) {
                Text(pointerSpeedDescription)
                    .foregroundStyle(.secondary)
            }
            LabeledContent(Localized.text("pointer.appliedDevices")) {
                Text(Localized.format(
                    "pointer.appliedDevicesValue",
                    model.pointerSnapshot.appliedDeviceCount,
                    model.pointerSnapshot.connectedDeviceCount))
                    .foregroundStyle(.secondary)
            }
            LabeledContent(Localized.text("pointer.health")) {
                Text(pointerHealthDescription)
                    .foregroundStyle(pointerHealthColor)
            }
            if let failureReason = model.pointerSnapshot.failureReason {
                LabeledContent(Localized.text("pointer.failureReason")) {
                    Text(failureReason.localizedDescription)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var systemSection: some View {
        Section(Localized.text("diagnostics.systemSection")) {
            DiagnosticRow(
                label: Localized.text("general.accessibility"),
                value: model.snapshot.accessibilityTrusted
                    ? Localized.text("general.granted")
                    : Localized.text("diagnostics.required"),
                systemImage: model.snapshot.accessibilityTrusted
                    ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                color: model.snapshot.accessibilityTrusted ? .green : .orange)
            DiagnosticRow(
                label: Localized.text("diagnostics.engine"),
                value: model.snapshot.engineEnabled
                    ? Localized.text("diagnostics.enabled")
                    : Localized.text("diagnostics.disabled"),
                systemImage: model.snapshot.engineEnabled ? "power.circle.fill" : "power.circle",
                color: model.snapshot.engineEnabled ? .green : .secondary)
            DiagnosticRow(
                label: Localized.text("diagnostics.eventTap"),
                value: eventTapLabel,
                systemImage: eventTapIcon,
                color: eventTapColor)
            LabeledContent(Localized.text("diagnostics.recoveries")) {
                Text(recoveryDescription)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var contextSection: some View {
        Section(Localized.text("diagnostics.contextSection")) {
            LabeledContent(Localized.text("diagnostics.pointerApp")) {
                if let bundleID = model.snapshot.pointerBundleID {
                    VStack(alignment: .trailing, spacing: 2) {
                        AppRow(bundleID: bundleID)
                        Text(bundleID)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                } else {
                    Text(Localized.text("diagnostics.notDetected"))
                        .foregroundStyle(.secondary)
                }
            }
            LabeledContent(Localized.text("diagnostics.lastAction")) {
                Text(lastActionDescription)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
        }
    }

    private var mouseSection: some View {
        Section(Localized.text("diagnostics.miceSection")) {
            if model.snapshot.detectedMice.isEmpty {
                Text(Localized.text("diagnostics.noMice"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.snapshot.detectedMice) { mouse in
                    Label(mouse.name, systemImage: "computermouse")
                }
            }
            Text(Localized.text("diagnostics.miceDescription"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var eventTapLabel: String {
        switch model.snapshot.eventTapHealth {
        case .initializing: return Localized.text("diagnostics.initializing")
        case .healthy: return Localized.text("diagnostics.healthy")
        case .recovering: return Localized.text("diagnostics.recovering")
        }
    }

    private var eventTapIcon: String {
        switch model.snapshot.eventTapHealth {
        case .initializing: return "clock.fill"
        case .healthy: return "checkmark.circle.fill"
        case .recovering: return "arrow.clockwise.circle.fill"
        }
    }

    private var eventTapColor: Color {
        switch model.snapshot.eventTapHealth {
        case .initializing: return .orange
        case .healthy: return .green
        case .recovering: return .blue
        }
    }

    private var recoveryDescription: String {
        guard let date = model.snapshot.lastRecoveryAt else {
            return Localized.format("diagnostics.recoveryCount", model.snapshot.recoveryCount)
        }
        let time = Self.timeFormatter.string(from: date)
        return Localized.format("diagnostics.recoveryCountAt", model.snapshot.recoveryCount, time)
    }

    private var lastActionDescription: String {
        guard let last = model.snapshot.lastAction else {
            return Localized.text("diagnostics.noAction")
        }
        return Localized.format(
            "diagnostics.lastActionValue",
            last.action.displayName,
            last.button,
            Self.timeFormatter.string(from: last.triggeredAt))
    }

    private var pointerProfileDescription: String {
        guard model.pointerSnapshot.managementEnabled else {
            return Localized.text("pointer.systemUnchanged")
        }
        guard let bundleID = model.pointerSnapshot.matchedProfileBundleID else {
            return Localized.text("pointer.globalProfile")
        }
        let name = InstalledApp.lookup(bundleID)?.name ?? bundleID
        return Localized.format("pointer.appProfile", name)
    }

    private var pointerAccelerationDescription: String {
        guard let enabled = model.pointerSnapshot.actualAccelerationEnabled else {
            return Localized.text("pointer.systemUnchanged")
        }
        return enabled
            ? Localized.text("pointer.override.enabled")
            : Localized.text("pointer.override.disabled")
    }

    private var pointerSpeedDescription: String {
        guard let speed = model.pointerSnapshot.actualSpeedMultiplier else {
            return Localized.text("pointer.systemUnchanged")
        }
        return Localized.format("pointer.speedValue", speed)
    }

    private var pointerTargetAccelerationDescription: String {
        guard let enabled = model.pointerSnapshot.accelerationEnabled else {
            return Localized.text("pointer.systemUnchanged")
        }
        return enabled
            ? Localized.text("pointer.override.enabled")
            : Localized.text("pointer.override.disabled")
    }

    private var pointerTargetSpeedDescription: String {
        guard model.pointerSnapshot.managementEnabled else {
            return Localized.text("pointer.systemUnchanged")
        }
        return Localized.format("pointer.speedValue", model.pointerSnapshot.speedMultiplier)
    }

    private var pointerHealthDescription: String {
        switch model.pointerSnapshot.health {
        case .inactive: return Localized.text("pointer.health.inactive")
        case .applied: return Localized.text("pointer.health.applied")
        case .unavailable: return Localized.text("pointer.health.unavailable")
        case .failed: return Localized.text("pointer.health.failed")
        case .drifted: return Localized.text("pointer.health.drifted")
        }
    }

    private var pointerHealthColor: Color {
        switch model.pointerSnapshot.health {
        case .inactive, .unavailable: return .secondary
        case .applied: return .green
        case .failed, .drifted: return .orange
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

struct DiagnosticsSummaryView: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let snapshot = EventTapEngine.shared.diagnosticsSnapshot()
            let healthy = snapshot.accessibilityTrusted
                && snapshot.eventTapHealth == .healthy
                && snapshot.engineEnabled
            Label(
                healthy
                    ? Localized.text("diagnostics.healthy")
                    : summaryLabel(snapshot),
                systemImage: healthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(healthy ? .green : .orange)
        }
    }

    private func summaryLabel(_ snapshot: EngineDiagnosticsSnapshot) -> String {
        if !snapshot.accessibilityTrusted { return Localized.text("diagnostics.required") }
        if !snapshot.engineEnabled { return Localized.text("diagnostics.disabled") }
        switch snapshot.eventTapHealth {
        case .initializing: return Localized.text("diagnostics.initializing")
        case .healthy: return Localized.text("diagnostics.healthy")
        case .recovering: return Localized.text("diagnostics.recovering")
        }
    }
}

private struct DiagnosticRow: View {
    let label: String
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        LabeledContent(label) {
            Label(value, systemImage: systemImage)
                .foregroundStyle(color)
        }
    }
}
