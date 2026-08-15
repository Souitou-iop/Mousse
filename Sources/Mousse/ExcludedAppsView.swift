import SwiftUI
import UniformTypeIdentifiers

/// Per-app scroll exceptions with only the two controls that differ from global behavior.
struct ExcludedAppsView: View {
    @EnvironmentObject var store: ConfigStore

    var body: some View {
        Section(Localized.text("apps.excluded")) {
            if store.config.scrollAppProfiles.isEmpty {
                Text(Localized.text("apps.noExcluded"))
                    .foregroundStyle(.secondary)
            }
            ForEach($store.config.scrollAppProfiles) { $profile in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        AppRow(bundleID: profile.bundleID)
                        Spacer()
                        Button {
                            store.config.scrollAppProfiles.removeAll { $0.id == profile.id }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(Localized.text("apps.remove"))
                    }
                    Toggle(Localized.text("apps.mousseScroll"),
                           isOn: $profile.mousseScrollEnabled)
                    Toggle(Localized.text("apps.reverseScroll"),
                           isOn: $profile.reverseScroll)
                }
            }
            Button(Localized.text("apps.add"), action: addApp)
            Text(Localized.text("apps.excludedDescription"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear(perform: migrateLegacyExclusions)
    }

    private func migrateLegacyExclusions() {
        guard !store.config.excludedBundleIDs.isEmpty else { return }
        var config = store.config
        let existing = Set(config.scrollAppProfiles.map(\.bundleID))
        config.scrollAppProfiles.append(contentsOf: config.excludedBundleIDs
            .filter { !existing.contains($0) }
            .map { ScrollAppProfile(bundleID: $0) })
        config.excludedBundleIDs = []
        store.config = config
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = Localized.text("apps.exclude")
        guard panel.runModal() == .OK else { return }
        let existing = Set(store.config.scrollAppProfiles.map(\.bundleID))
        for url in panel.urls {
            guard let id = Bundle(url: url)?.bundleIdentifier,
                  !existing.contains(id),
                  !store.config.scrollAppProfiles.contains(where: { $0.bundleID == id }) else {
                continue
            }
            store.config.scrollAppProfiles.append(ScrollAppProfile(bundleID: id))
        }
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
