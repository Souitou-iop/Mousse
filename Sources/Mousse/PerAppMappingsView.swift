import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Per-app button mappings. The app is resolved from the window under the mouse pointer at click
/// time; buttons without a per-app mapping keep their global behavior.
struct PerAppMappingsView: View {
    @EnvironmentObject var store: ConfigStore
    @State private var editingID: UUID?

    var body: some View {
        if let editingID,
           let index = store.config.perAppMappings.firstIndex(where: { $0.id == editingID }) {
            PerAppEditorView(
                app: $store.config.perAppMappings[index],
                holdDuration: $store.config.holdDuration,
                doubleClickInterval: $store.config.doubleClickInterval,
                onBack: { self.editingID = nil })
        } else {
            appList
        }
    }

    private var appList: some View {
        Form {
            Section(Localized.text("apps.perAppSection")) {
                if store.config.perAppMappings.isEmpty {
                    Text(Localized.text("apps.noPerApp"))
                        .foregroundStyle(.secondary)
                }
                ForEach($store.config.perAppMappings) { $app in
                    HStack {
                        AppRow(bundleID: app.bundleID)
                        Spacer()
                        Button(Localized.text("apps.edit")) { editingID = app.id }
                        Button(Localized.text("common.delete"), role: .destructive) {
                            remove(app)
                        }
                    }
                }
                Button(Localized.text("apps.addPerApp"), action: addApp)
                Text(Localized.text("apps.perAppDescription"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = Localized.text("apps.addPerApp")
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        guard !store.config.perAppMappings.contains(where: { $0.bundleID == bundleID }) else { return }
        store.config.perAppMappings.append(AppMappings(bundleID: bundleID))
    }

    private func remove(_ app: AppMappings) {
        store.config.perAppMappings.removeAll { $0.id == app.id }
    }
}

private struct PerAppEditorView: View {
    @Binding var app: AppMappings
    @Binding var holdDuration: Double
    @Binding var doubleClickInterval: Double
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: onBack) {
                    Label(Localized.text("common.back"), systemImage: "chevron.left")
                }
                Spacer()
                AppRow(bundleID: app.bundleID)
            }
            .padding(.bottom, 4)

            MappingEditor(
                mappings: $app.mappings,
                configuredButtons: $app.configuredButtons,
                holdDuration: $holdDuration,
                doubleClickInterval: $doubleClickInterval)
        }
        .padding()
    }
}
