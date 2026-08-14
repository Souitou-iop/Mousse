import Foundation

/// Compiled button mappings for one scope (global or one app), plus the hold-scroll table.
/// `.none` mappings are unconfigured placeholders — excluded here, so the button keeps its normal
/// behavior until the user picks an action.
struct CompiledButtonMappings: Equatable {
    var actionsByButton: [Int: ButtonTriggerRecognizer.Actions] = [:]
    var holdScrollByButton: [Int: RemapAction.ScrollOutput] = [:]
}

/// Turns `AppConfig` mappings into per-button recognizer tables. Per-app mappings only override the
/// buttons actually configured there; every other button falls back to the global mapping.
struct ButtonMappingResolver {
    private var global: CompiledButtonMappings
    private var perApp: [String: CompiledButtonMappings]

    init(config: AppConfig) {
        global = Self.compile(config.mappings)
        // Imported or hand-edited local files may contain duplicate bundle IDs. The strict import
        // path rejects those, but runtime compilation must still never trap on persisted data.
        // Match normal assignment semantics: the last profile wins deterministically.
        var compiled: [String: CompiledButtonMappings] = [:]
        for app in config.perAppMappings {
            compiled[app.bundleID] = Self.compile(app.mappings)
        }
        perApp = compiled
    }

    var hasPerAppMappings: Bool { !perApp.isEmpty }

    /// Resolve the effective tables for the app under the cursor (`nil` = no app override matched).
    func resolved(for bundleID: String?) -> CompiledButtonMappings {
        guard let bundleID, let app = perApp[bundleID] else { return global }
        var merged = global
        for (button, actions) in app.actionsByButton { merged.actionsByButton[button] = actions }
        for (button, output) in app.holdScrollByButton { merged.holdScrollByButton[button] = output }
        return merged
    }

    private static func compile(_ mappings: [ButtonMapping]) -> CompiledButtonMappings {
        var compiled = CompiledButtonMappings()
        compiled.actionsByButton = Dictionary(grouping: mappings, by: \.buttonNumber).compactMapValues { mappings in
            let actions = ButtonTriggerRecognizer.Actions(
                click: mappings.first(where: { $0.trigger == .click && $0.action != .none })?.action,
                doubleClick: mappings.first(where: { $0.trigger == .doubleClick && $0.action != .none })?.action,
                hold: mappings.first(where: { $0.trigger == .hold && $0.action != .none && !$0.action.isScrollOutput })?.action)
            return (actions.click != nil || actions.doubleClick != nil || actions.hold != nil)
                ? actions : nil
        }
        for m in mappings where m.trigger == .hold {
            if case let .scrollOutput(output) = m.action { compiled.holdScrollByButton[m.buttonNumber] = output }
        }
        return compiled
    }
}
