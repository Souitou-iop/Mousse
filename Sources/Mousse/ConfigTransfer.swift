import Foundation

enum ConfigTransferError: LocalizedError, Equatable {
    case invalidTopLevel
    case duplicateAppProfile(String)

    var errorDescription: String? {
        switch self {
        case .invalidTopLevel:
            return Localized.text("config.importInvalidTopLevel")
        case let .duplicateAppProfile(bundleID):
            return Localized.format("config.importDuplicateAppProfile", bundleID)
        }
    }
}

/// JSON import/export for the whole `AppConfig`. The file is just the same encoding the app
/// already writes locally, so an exported file can also be dropped in as `config.json` manually,
/// and a future iCloud sync layer only needs to copy that one file around.
enum ConfigTransfer {
    static func export(_ config: AppConfig, to url: URL) throws {
        let data = try JSONEncoder().encode(config)
        try data.write(to: url, options: .atomic)
    }

    static func importConfig(from url: URL) throws -> AppConfig {
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data)
        guard json is [String: Any] else { throw ConfigTransferError.invalidTopLevel }

        let config = try JSONDecoder().decode(AppConfig.self, from: data)
        var bundleIDs = Set<String>()
        for profile in config.pointerAppProfiles
            where !bundleIDs.insert(profile.bundleID).inserted {
            throw ConfigTransferError.duplicateAppProfile(profile.bundleID)
        }
        bundleIDs.removeAll()
        for profile in config.scrollAppProfiles
            where !bundleIDs.insert(profile.bundleID).inserted {
            throw ConfigTransferError.duplicateAppProfile(profile.bundleID)
        }
        return config
    }
}
