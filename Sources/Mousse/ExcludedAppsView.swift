import SwiftUI
import UniformTypeIdentifiers

/// Collapsible group for all per-app scroll exceptions.
struct AppExceptionsGroupView: View {
    @EnvironmentObject var store: ConfigStore
    @State private var isExpanded = false

    var body: some View {
        Section {
            DisclosureGroup(Localized.text("apps.exceptionsSection"), isExpanded: $isExpanded) {
                ExcludedAppsContent()
                Divider()
                TransposedAppsContent()
                Divider()
                RemoteDesktopAppsContent()
            }
        }
    }
}

/// Content for general excluded apps.
struct ExcludedAppsContent: View {
    @EnvironmentObject var store: ConfigStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Localized.text("apps.excluded"))
                .font(.headline)
            if store.config.scrollAppProfiles.isEmpty {
                Text(Localized.text("apps.noExcluded"))
                    .foregroundStyle(.secondary)
            }
            ForEach($store.config.scrollAppProfiles) { $profile in
                VStack(alignment: .leading, spacing: 6) {
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

/// Content for axis-swapped apps.
struct TransposedAppsContent: View {
    @EnvironmentObject var store: ConfigStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Localized.text("apps.axisSwap"))
                .font(.headline)
            AppListContent(bundleIDs: $store.config.verticalToHorizontalBundleIDs,
                           emptyLabel: Localized.text("apps.noAxisSwap"),
                           addPrompt: Localized.text("common.add"))
            Text(Localized.text("apps.axisSwapDescription"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Content for remote desktop and virtual machine bypass.
struct RemoteDesktopAppsContent: View {
    @EnvironmentObject var store: ConfigStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Localized.text("apps.remoteDesktop"))
                .font(.headline)
            Toggle(Localized.text("apps.remoteDesktopBypass"),
                   isOn: $store.config.remoteDesktopBypass)
            if store.config.remoteDesktopBypass {
                AppListContent(bundleIDs: $store.config.remoteDesktopBundleIDs,
                               emptyLabel: Localized.text("apps.noRemoteDesktop"),
                               addPrompt: Localized.text("common.add"))
            }
            Text(Localized.text("apps.remoteDesktopDescription"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Collapsible group for gaming and pointer lock auto-bypass.
struct GameBypassGroupView: View {
    @EnvironmentObject var store: ConfigStore
    @State private var isExpanded = false

    var body: some View {
        Section {
            DisclosureGroup(Localized.text("apps.games"), isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(Localized.text("apps.gameBypass"),
                           isOn: $store.config.gameBypass)
                    if store.config.gameBypass {
                        AppListContent(bundleIDs: $store.config.gameBundleIDs,
                                       emptyLabel: Localized.text("apps.noGames"),
                                       addPrompt: Localized.text("common.add"))
                    }
                    Text(Localized.text("apps.gameBypassDescription"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// One reusable per-app list content view without outer section wrapper.
struct AppListContent: View {
    @Binding var bundleIDs: [String]
    let emptyLabel: String
    let addPrompt: String

    var body: some View {
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
