import SwiftUI
import AppKit

/// Starts event-tap capture and reports the first physical mouse button pressed.
struct ButtonCaptureField: View {
    var onCapture: (Int) -> Void

    @State private var capturing = false
    @State private var escapeMonitor: Any?
    @State private var startError: EventTapEngine.CaptureStartStatus?
    @State private var endMessageKey: String?

    var body: some View {
        VStack(spacing: 4) {
            Button(action: toggle) {
                HStack {
                    Image(systemName: capturing ? "cursorarrow.click.badge.clock" : "plus.circle.fill")
                    Text(capturing
                         ? Localized.text("buttons.captureActive")
                         : Localized.text("buttons.capturePrompt"))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .foregroundStyle(capturing ? .orange : .accentColor)
            }
            if startError == .accessibilityRequired {
                Button(Localized.text("capture.openAccessibility")) { AccessibilityPermission.openSettings() }
                    .font(.caption)
            } else if startError == .eventTapInitializing {
                Text(Localized.text("capture.eventTapInitializing"))
                    .font(.caption).foregroundStyle(.secondary)
            } else if let endMessageKey {
                Text(Localized.text(endMessageKey))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onDisappear { stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            stop()
        }
    }

    private func toggle() { capturing ? stop() : start() }

    private func start() {
        startError = nil
        endMessageKey = nil
        let status = EventTapEngine.shared.beginCapture { outcome in
            guard capturing else { return }
            finishUI()
            switch outcome {
            case let .captured(result): onCapture(result)
            case .cancelled: endMessageKey = "capture.cancelled"
            case .timedOut: endMessageKey = "capture.timedOut"
            }
        }
        guard status == .started else {
            startError = status
            return
        }
        capturing = true
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil }
            return event
        }
    }

    private func stop() {
        guard capturing else { return }
        finishUI()
        endMessageKey = "capture.cancelled"
        EventTapEngine.shared.cancelCapture()
    }

    private func finishUI() {
        capturing = false
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
    }
}
