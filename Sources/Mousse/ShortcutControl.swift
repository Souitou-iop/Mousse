import SwiftUI
import AppKit

/// Shows a mapping's action and lets the user either pick a preset or record a custom shortcut.
/// Recording uses a HID event tap so the shortcut is swallowed before any app receives it.
struct ShortcutControl: View {
    @Binding var action: RemapAction
    /// Hold-and-scroll outputs only make sense for the .hold trigger (the engine routes wheel
    /// input only for those mappings) — hide them from the preset menu otherwise.
    var showScrollOutputs = false
    @State private var recording = false
    @State private var startError: EventTapEngine.CaptureStartStatus?
    @State private var endMessageKey: String?

    var body: some View {
        Group {
            if recording {
                Button(Localized.text("buttons.pressKeys")) { stopRecording() }
                    .foregroundStyle(.orange)
            } else {
                Menu(action.displayName) {
                    Section(Localized.text("buttons.presets")) {
                        ForEach(RemapAction.presets.filter { showScrollOutputs || !$0.isScrollOutput },
                                id: \.self) { preset in
                            Button(preset.displayName) { action = preset }
                        }
                    }
                    Divider()
                    Button(Localized.text("buttons.recordShortcut")) { startRecording() }
                }
            }
        }
        .frame(width: 190)
        .overlay(alignment: .bottom) {
            if startError == .accessibilityRequired {
                Button(Localized.text("capture.openAccessibility")) { AccessibilityPermission.openSettings() }
                    .font(.caption2).offset(y: 18)
            } else if startError == .eventTapInitializing {
                Text(Localized.text("capture.eventTapInitializing"))
                    .font(.caption2).foregroundStyle(.secondary).offset(y: 18)
            } else if let endMessageKey {
                Text(Localized.text(endMessageKey))
                    .font(.caption2).foregroundStyle(.secondary).offset(y: 18)
            }
        }
        .onDisappear { stopRecording() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            stopRecording()
        }
    }

    private func startRecording() {
        startError = nil
        endMessageKey = nil
        let status = EventTapEngine.shared.beginKeyboardCapture { outcome in
            guard recording else { return }
            recording = false
            switch outcome {
            case let .captured(result): action = result.action
            case .cancelled: endMessageKey = "capture.cancelled"
            case .timedOut: endMessageKey = "capture.timedOut"
            }
        }
        guard status == .started else {
            startError = status
            return
        }
        recording = true
    }

    private func stopRecording() {
        guard recording else { return }
        recording = false
        endMessageKey = "capture.cancelled"
        EventTapEngine.shared.cancelCapture()
    }
}
