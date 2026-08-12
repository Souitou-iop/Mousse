import Foundation

enum AppLanguage: String, Codable, Sendable, CaseIterable {
    case system
    case english
    case simplifiedChinese

    var label: String {
        switch self {
        case .system: return Localized.text("general.language.system")
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        }
    }
}

enum Localized {
    static var language: AppLanguage = .system

    private static var usesSimplifiedChinese: Bool {
        switch language {
        case .simplifiedChinese:
            return true
        case .english:
            return false
        case .system:
            return Locale.preferredLanguages.contains { language in
                let normalized = language.replacingOccurrences(of: "_", with: "-").lowercased()
                return normalized.hasPrefix("zh-hans") || normalized.hasPrefix("zh-cn")
            }
        }
    }

    private static var bundle: Bundle {
        if usesSimplifiedChinese,
           let path = Bundle.module.path(forResource: "zh-hans", ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return Bundle.module
    }

    static func text(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        let locale = usesSimplifiedChinese ? Locale(identifier: "zh_CN") : Locale(identifier: "en_US")
        return String(format: text(key), locale: locale, arguments: arguments)
    }
}
