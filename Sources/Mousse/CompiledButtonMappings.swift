import Foundation

/// Compiled global button mappings, plus the hold-scroll table.
/// `.none` mappings are unconfigured placeholders — excluded here, so the button keeps its normal
/// behavior until the user picks an action.
struct CompiledButtonMappings: Equatable {
    var actionsByButton: [Int: ButtonTriggerRecognizer.Actions] = [:]
    var holdScrollByButton: [Int: RemapAction.ScrollOutput] = [:]

    init(_ mappings: [ButtonMapping]) {
        actionsByButton = Dictionary(grouping: mappings, by: \.buttonNumber).compactMapValues { mappings in
            let actions = ButtonTriggerRecognizer.Actions(
                click: mappings.first(where: { $0.trigger == .click && $0.action != .none })?.action,
                doubleClick: mappings.first(where: { $0.trigger == .doubleClick && $0.action != .none })?.action,
                hold: mappings.first(where: { $0.trigger == .hold && $0.action != .none && !$0.action.isScrollOutput })?.action)
            return (actions.click != nil || actions.doubleClick != nil || actions.hold != nil)
                ? actions : nil
        }
        for mapping in mappings where mapping.trigger == .hold {
            if case let .scrollOutput(output) = mapping.action {
                holdScrollByButton[mapping.buttonNumber] = output
            }
        }
    }
}
