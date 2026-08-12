import SwiftUI

/// Button mappings grouped by physical button, with one action per trigger type.
struct ButtonMappingsView: View {
    @EnvironmentObject var store: ConfigStore
    @State private var highlightedMappingID: UUID?

    private var buttons: [Int] {
        Array(Set(store.config.mappings.map(\.buttonNumber))).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ButtonCaptureField(onCapture: addButton)

            if store.config.mappings.isEmpty {
                ContentUnavailableView(Localized.text("buttons.noMappings"), systemImage: "computermouse",
                                       description: Text(Localized.text("buttons.noMappingsDescription")))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(buttons, id: \.self) { button in
                            Section {
                                ForEach(ButtonTrigger.allCases, id: \.self) { trigger in
                                    if let index = mappingIndex(button: button, trigger: trigger) {
                                        MappingRow(
                                            mapping: $store.config.mappings[index],
                                            missingTriggers: missingTriggers(for: button),
                                            highlighted: highlightedMappingID == store.config.mappings[index].id,
                                            onAddTrigger: { addTrigger($0, to: button) },
                                            onDelete: { store.config.mappings.remove(at: index) }
                                        )
                                        .id(store.config.mappings[index].id)
                                    }
                                }
                            } header: {
                                Label(Localized.format("common.button", button), systemImage: "computermouse.fill")
                            }
                        }
                    }
                    .listStyle(.inset)
                    .onChange(of: highlightedMappingID) { _, id in
                        guard let id else { return }
                        withAnimation { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }

            Divider()
            timingControls
        }
    }

    private var timingControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Stepper(value: $store.config.doubleClickInterval, in: 0.10...0.50, step: 0.01) {
                Text(Localized.format("buttons.doubleClickInterval",
                                      Int((store.config.doubleClickInterval * 1000).rounded())))
            }
            Stepper(value: $store.config.holdDuration, in: 0.10...0.80, step: 0.01) {
                Text(Localized.format("buttons.holdDuration",
                                      Int((store.config.holdDuration * 1000).rounded())))
            }
            Text(Localized.text("buttons.timingDescription"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func mappingIndex(button: Int, trigger: ButtonTrigger) -> Int? {
        store.config.mappings.firstIndex {
            $0.buttonNumber == button && $0.trigger == trigger
        }
    }

    private func missingTriggers(for button: Int) -> [ButtonTrigger] {
        ButtonTrigger.allCases.filter { mappingIndex(button: button, trigger: $0) == nil }
    }

    private func addButton(_ result: ButtonCaptureRecognizer.Result) {
        guard result.buttonNumber >= 3 else { return }
        if let index = mappingIndex(button: result.buttonNumber, trigger: result.trigger) {
            highlight(store.config.mappings[index].id)
            return
        }
        let mapping = ButtonMapping(buttonNumber: result.buttonNumber, trigger: result.trigger,
                                    action: .spaceLeft)
        store.config.mappings.append(mapping)
        highlight(mapping.id)
    }

    private func addTrigger(_ trigger: ButtonTrigger, to button: Int) {
        guard mappingIndex(button: button, trigger: trigger) == nil else { return }
        store.config.mappings.append(ButtonMapping(buttonNumber: button, trigger: trigger,
                                                   action: .spaceLeft))
    }

    private func highlight(_ id: UUID) {
        highlightedMappingID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if highlightedMappingID == id { highlightedMappingID = nil }
        }
    }
}

private struct MappingRow: View {
    @Binding var mapping: ButtonMapping
    let missingTriggers: [ButtonTrigger]
    let highlighted: Bool
    let onAddTrigger: (ButtonTrigger) -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(mapping.trigger.label)
                .frame(width: 72, alignment: .leading)

            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            ShortcutControl(action: $mapping.action)
            Spacer()

            if !missingTriggers.isEmpty {
                Menu {
                    ForEach(missingTriggers, id: \.self) { trigger in
                        Button(trigger.label) { onAddTrigger(trigger) }
                    }
                } label: {
                    Image(systemName: "plus.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(Localized.text("buttons.addTrigger"))
            }

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(Localized.text("buttons.removeMapping"))
        }
        .padding(.vertical, 2)
        .listRowBackground(highlighted ? Color.accentColor.opacity(0.16) : Color.clear)
    }
}
