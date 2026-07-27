import SwiftUI
import AppKit

/// "Click here with a mouse button" field — captures which physical button you press (like ),
/// so you never have to guess button numbers. Reports the 1-based button number via `onCapture`.
struct ButtonCaptureField: View {
    var onCapture: (Int) -> Void

    @State private var capturing = false
    @State private var localMonitor: Any?
    /// A LOCAL monitor only sees events delivered to this app. If the capture click lands over
    /// another app's window (the user switched away, or the pointer simply isn't over Settings),
    /// the local monitor never fires — capture would stay on and every button mapping plus the
    /// Space-drag gesture stays bypassed. The global monitor covers exactly that case.
    @State private var globalMonitor: Any?
    /// Last resort if neither monitor ever fires (no click at all, window torn down without
    /// `onDisappear`). Shorter than the engine's own capture expiry so the UI resets first.
    @State private var timeout: DispatchWorkItem?
    private static let captureTimeout = 20.0

    var body: some View {
        Button(action: toggle) {
            HStack {
                Image(systemName: capturing ? "cursorarrow.click.badge.clock" : "plus.circle.fill")
                Text(capturing
                     ? "Now click the mouse button you want…  (⎋ cancels)"
                     : "Click here with a mouse button to add a mapping")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .foregroundStyle(capturing ? .orange : .accentColor)
        }
        .onDisappear { stop() }
    }

    private func toggle() { capturing ? stop() : start() }

    private func start() {
        capturing = true
        EventTapEngine.shared.setCaptureMode(true) // let the click reach this window
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown, .keyDown]) { event in
            if event.type == .keyDown {
                if event.keyCode == 53 { stop(); return nil } // Esc cancels
                return event
            }
            capture(event.buttonNumber + 1) // 0-based → 1-based (middle = 3, side = 4/5…)
            return nil // swallow the captured click
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.otherMouseDown]) { event in
            // Global events can't be swallowed — the other app already got this click. Recording
            // the button anyway is what the user asked for, and beats leaving capture stranded.
            capture(event.buttonNumber + 1)
        }
        let expiry = DispatchWorkItem { stop() }
        timeout = expiry
        DispatchQueue.main.asyncAfter(deadline: .now() + ButtonCaptureField.captureTimeout,
                                      execute: expiry)
    }

    /// Record a captured button and close capture. Guarded so the local and global monitors can't
    /// both fire for one click and add the mapping twice.
    private func capture(_ button: Int) {
        guard capturing else { return }
        stop()
        onCapture(button)
    }

    private func stop() {
        capturing = false
        EventTapEngine.shared.setCaptureMode(false)
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        timeout?.cancel()
        timeout = nil
    }
}
