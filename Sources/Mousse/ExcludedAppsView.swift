import SwiftUI
import UniformTypeIdentifiers

/// Apps where Mousse leaves physical wheel events completely untouched.
struct ExcludedAppsView: View {
    @EnvironmentObject var store: ConfigStore

    var body: some View {
        AppListSection(
            title: Localized.text("apps.excluded"),
            emptyLabel: Localized.text("apps.noExcluded"),
            addPrompt: Localized.text("apps.exclude"),
            footer: Localized.text("apps.excludedDescription"),
            bundleIDs: $store.config.excludedBundleIDs)
    }
}

/// Settings section for the axis-swap list: apps where the wheel's vertical motion scrolls
/// HORIZONTALLY (purpose-built for horizontal-first browsers like Nimble Commander's Brief
/// panels). Unlike exclusion, smoothing keeps working — we transpose the axes ourselves.
struct TransposedAppsView: View {
    @EnvironmentObject var store: ConfigStore

    var body: some View {
        AppListSection(
            title: Localized.text("apps.axisSwap"),
            emptyLabel: Localized.text("apps.noAxisSwap"),
            addPrompt: Localized.text("common.add"),
            footer: Localized.text("apps.axisSwapDescription"),
            bundleIDs: $store.config.verticalToHorizontalBundleIDs)
    }
}

/// One reusable per-app list section: rows with app icon/name, remove buttons, an add-app picker.
private struct AppListSection: View {
    let title: String
    let emptyLabel: String
    let addPrompt: String
    let footer: String
    @Binding var bundleIDs: [String]

    var body: some View {
        Section(title) {
            if bundleIDs.isEmpty {
                Text(emptyLabel)
                    .foregroundStyle(.secondary)
            }
            ForEach(bundleIDs, id: \.self) { bundleID in
                HStack {
                    AppRow(bundleID: bundleID)
                    Spacer()
                    Button {
                        bundleIDs.removeAll { $0 == bundleID }
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(Localized.text("apps.remove"))
                }
            }
            Button(Localized.text("apps.add"), action: addApp)
            Text(footer)
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = addPrompt
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let id = Bundle(url: url)?.bundleIdentifier,
                  !bundleIDs.contains(id) else { continue }
            bundleIDs.append(id)
        }
    }
}

/// One listed app: icon + display name when the app is installed, otherwise the raw bundle ID.
private struct AppRow: View {
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
/// including once per step while dragging the scroll-speed slider. Resolving it inline meant a
/// LaunchServices query plus icon and display-name lookups (disk I/O) per listed app per frame,
/// which is exactly the kind of work a view body must not do. The set of installed apps barely
/// changes while a Settings window is open, so a plain memo is the whole fix.
@MainActor
private struct InstalledApp {
    let icon: NSImage
    let name: String

    private static var cache: [String: InstalledApp?] = [:]

    static func lookup(_ bundleID: String) -> InstalledApp? {
        if let memoized = cache[bundleID] { return memoized }
        let resolved = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map {
            InstalledApp(icon: NSWorkspace.shared.icon(forFile: $0.path),
                         name: FileManager.default.displayName(atPath: $0.path))
        }
        cache[bundleID] = resolved
        return resolved
    }
}
