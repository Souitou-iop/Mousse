import AppKit
import SwiftUI

/// One listed app: icon + display name when the app is installed, otherwise the raw bundle ID.
struct AppRow: View {
    let bundleID: String

    var body: some View {
        HStack(spacing: 6) {
            if let app = InstalledApp.lookup(bundleID) {
                Image(nsImage: app.icon).resizable().frame(width: 18, height: 18)
                Text(app.name)
            } else {
                Image(systemName: "questionmark.app").frame(width: 18, height: 18)
                Text(bundleID).foregroundStyle(.secondary)
            }
        }
    }
}

/// Icon + display name for a bundle ID, resolved once and memoized.
///
/// This is read from a SwiftUI `body`, which re-runs on every re-render of the Settings form —
/// including once per step while dragging a slider. Resolving it inline meant a LaunchServices
/// query plus icon and display-name lookups (disk I/O) per listed app per frame, which is exactly
/// the kind of work a view body must not do. The set of installed apps barely changes while a
/// Settings window is open, so a plain memo is the whole fix.
@MainActor
struct InstalledApp {
    let icon: NSImage
    let name: String

    private static var cache: [String: InstalledApp?] = [:]

    static func lookup(
        _ bundleID: String,
        resolve: @MainActor (String) -> InstalledApp? = resolveInstalledApp
    ) -> InstalledApp? {
        if let memoized = cache[bundleID] { return memoized }
        let resolved = resolve(bundleID)
        // Dictionary subscript assignment with nil removes the key. `updateValue` stores the
        // optional nil as the value, so a failed LaunchServices lookup is cached too.
        cache.updateValue(resolved, forKey: bundleID)
        return resolved
    }

    private static func resolveInstalledApp(_ bundleID: String) -> InstalledApp? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map {
            InstalledApp(icon: NSWorkspace.shared.icon(forFile: $0.path),
                         name: FileManager.default.displayName(atPath: $0.path))
        }
    }
}
