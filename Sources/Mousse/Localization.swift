import Foundation

enum Localized {
    private static var bundle: Bundle {
        let prefersSimplifiedChinese = Locale.preferredLanguages.contains { language in
            let normalized = language.replacingOccurrences(of: "_", with: "-").lowercased()
            return normalized.hasPrefix("zh-hans") || normalized.hasPrefix("zh-cn")
        }

        if prefersSimplifiedChinese,
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
        String(format: text(key), locale: Locale.current, arguments: arguments)
    }
}
