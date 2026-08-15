import Foundation

enum AppLanguage: String, Codable, Sendable, CaseIterable {
    case system
    case english
    case simplifiedChinese
    case japanese
    case korean
    case spanish

    var label: String {
        switch self {
        case .system: return "System Default"
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .spanish: return "Español"
        }
    }

    var bundleCode: String {
        switch self {
        case .system: return ""
        case .english: return "en"
        case .simplifiedChinese: return "zh-Hans"
        case .japanese: return "ja"
        case .korean: return "ko"
        case .spanish: return "es"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .system: return ""
        case .english: return "en_US"
        case .simplifiedChinese: return "zh_CN"
        case .japanese: return "ja_JP"
        case .korean: return "ko_KR"
        case .spanish: return "es_ES"
        }
    }
}

enum Localized {
    static var language: AppLanguage = .system

    private static var resourceBundle: Bundle {
        if let url = Bundle.main.url(forResource: "Mousse_Mousse", withExtension: "bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return Bundle.module
    }

    private static var resolvedLanguage: AppLanguage {
        guard language == .system else { return language }
        let preferred = Locale.preferredLanguages.first ?? ""
        let normalized = preferred.replacingOccurrences(of: "_", with: "-").lowercased()
        if normalized.hasPrefix("zh-hans") || normalized.hasPrefix("zh-cn") {
            return .simplifiedChinese
        }
        if normalized.hasPrefix("ja") { return .japanese }
        if normalized.hasPrefix("ko") { return .korean }
        if normalized.hasPrefix("es") { return .spanish }
        return .english
    }

    private static var bundle: Bundle {
        let code = resolvedLanguage.bundleCode
        if !code.isEmpty,
           let path = localizedBundlePath(for: code),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return resourceBundle
    }

    /// SwiftPM normalizes `zh-Hans.lproj` to `zh-hans.lproj`, so an exact `Bundle.path` lookup can
    /// silently miss a language whose canonical spelling differs in case. Match case-insensitively
    /// instead of trusting the directory name's exact casing.
    private static func localizedBundlePath(for code: String) -> String? {
        if let exact = resourceBundle.path(forResource: code, ofType: "lproj") {
            return exact
        }
        let wanted = code.lowercased() + ".lproj"
        guard let entries = try? FileManager.default
            .contentsOfDirectory(atPath: resourceBundle.bundlePath) else { return nil }
        return entries.first { $0.lowercased() == wanted }
            .map { resourceBundle.bundlePath + "/" + $0 }
    }

    static func text(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        let locale = Locale(identifier: resolvedLanguage.localeIdentifier)
        return String(format: text(key), locale: locale, arguments: arguments)
    }
}
