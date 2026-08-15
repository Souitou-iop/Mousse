import SwiftUI

/// Global button mappings grouped by physical button, with one action per trigger type.
struct ButtonMappingsView: View {
    @EnvironmentObject var store: ConfigStore

    var body: some View {
        MappingEditor(
            mappings: $store.config.mappings,
            configuredButtons: $store.config.configuredButtons,
            holdDuration: $store.config.holdDuration,
            doubleClickInterval: $store.config.doubleClickInterval)
    }
}

/// Reusable button mapping editor, backed by explicit bindings so both the global page and the
/// per-app page can edit the same UI without duplicating the capture/grouping logic.
struct MappingEditor: View {
    @Binding var mappings: [ButtonMapping]
    @Binding var configuredButtons: [Int]
    @Binding var holdDuration: Double
    @Binding var doubleClickInterval: Double

    @State private var highlightedButton: Int?
    @State private var buttonPendingDeletion: Int?

    private var buttons: [Int] {
        configuredButtons
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ButtonCaptureField(onCapture: addButton)

            if buttons.isEmpty {
                ContentUnavailableView(Localized.text("buttons.noMappings"), systemImage: "computermouse",
                                       description: Text(Localized.text("buttons.noMappingsDescription")))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(buttons, id: \.self) { button in
                            Section {
                                if mappings(for: button).isEmpty {
                                    Text(Localized.text("buttons.noTriggers"))
                                        .foregroundStyle(.secondary)
                                }
                                ForEach(ButtonTrigger.allCases, id: \.self) { trigger in
                                    if let index = mappingIndex(button: button, trigger: trigger) {
                                        MappingRow(
                                            mapping: $mappings[index],
                                            onDelete: { mappings.remove(at: index) }
                                        )
                                    }
                                }
                            } header: {
                                HStack {
                                    Label(Localized.format("common.button", button),
                                          systemImage: "computermouse.fill")
                                    Spacer()
                                    if !missingTriggers(for: button).isEmpty {
                                        Menu {
                                            ForEach(missingTriggers(for: button), id: \.self) { trigger in
                                                Button(trigger.label) { addTrigger(trigger, to: button) }
                                            }
                                        } label: {
                                            Image(systemName: "plus.circle")
                                        }
                                        .menuStyle(.borderlessButton)
                                        .fixedSize()
                                        .help(Localized.text("buttons.addTrigger"))
                                    }
                                    Button(Localized.text("common.delete"), role: .destructive) {
                                        buttonPendingDeletion = button
                                    }
                                    .buttonStyle(.borderless)
                                    .foregroundStyle(.red)
                                    .help(Localized.text("buttons.removeButton"))
                                }
                            }
                            .id(button)
                            .listRowBackground(highlightedButton == button
                                               ? Color.accentColor.opacity(0.16) : Color.clear)
                        }
                    }
                    .listStyle(.inset)
                    .onChange(of: highlightedButton) { _, button in
                        guard let button else { return }
                        withAnimation { proxy.scrollTo(button, anchor: .center) }
                    }
                }
            }

            Divider()
            timingControls
        }
        .alert(Localized.text("buttons.removeButtonTitle"),
               isPresented: Binding(
                   get: { buttonPendingDeletion != nil },
                   set: { if !$0 { buttonPendingDeletion = nil } }
               )) {
            Button(Localized.text("common.cancel"), role: .cancel) {
                buttonPendingDeletion = nil
            }
            Button(Localized.text("common.delete"), role: .destructive) {
                if let buttonPendingDeletion { removeButton(buttonPendingDeletion) }
            }
        } message: {
            Text(Localized.text("buttons.removeButtonMessage"))
        }
    }

    private var timingControls: some View {
        HStack(spacing: 16) {
            Stepper(value: $holdDuration, in: 0.10...0.80, step: 0.01) {
                Text(Localized.format("buttons.holdDuration",
                                      Int((holdDuration * 1000).rounded())))
            }
            Spacer(minLength: 8)
            Stepper(value: $doubleClickInterval, in: 0.10...0.50, step: 0.01) {
                Text(Localized.format("buttons.doubleClickInterval",
                                      Int((doubleClickInterval * 1000).rounded())))
            }
        }
    }

    private func mappingIndex(button: Int, trigger: ButtonTrigger) -> Int? {
        mappings.firstIndex {
            $0.buttonNumber == button && $0.trigger == trigger
        }
    }

    private func missingTriggers(for button: Int) -> [ButtonTrigger] {
        ButtonTrigger.allCases.filter { mappingIndex(button: button, trigger: $0) == nil }
    }

    private func mappings(for button: Int) -> [ButtonMapping] {
        mappings.filter { $0.buttonNumber == button }
    }

    private func addButton(_ button: Int) {
        guard button >= 3 else { return }
        if !configuredButtons.contains(button) {
            configuredButtons.append(button)
            configuredButtons.sort()
        }
        highlight(button)
    }

    private func addTrigger(_ trigger: ButtonTrigger, to button: Int) {
        guard mappingIndex(button: button, trigger: trigger) == nil else { return }
        // Start unconfigured — the user picks the action explicitly instead of inheriting a
        // default. The engine ignores `.none` mappings, so the button keeps its normal behavior
        // until an action is chosen.
        mappings.append(ButtonMapping(buttonNumber: button, trigger: trigger,
                                      action: .none))
    }

    private func removeButton(_ button: Int) {
        mappings.removeAll { $0.buttonNumber == button }
        configuredButtons.removeAll { $0 == button }
        buttonPendingDeletion = nil
    }

    private func highlight(_ button: Int) {
        highlightedButton = button
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if highlightedButton == button { highlightedButton = nil }
        }
    }
}

private struct MappingRow: View {
    @Binding var mapping: ButtonMapping
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(mapping.trigger.label)
                .frame(width: 72, alignment: .leading)

            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)

            Spacer()

            ShortcutControl(action: $mapping.action,
                            showScrollOutputs: mapping.trigger == .hold)

            Spacer()

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(Localized.text("buttons.removeMapping"))
        }
        .padding(.vertical, 2)
    }
}
