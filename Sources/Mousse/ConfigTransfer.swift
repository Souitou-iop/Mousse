import Foundation

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
        return try JSONDecoder().decode(AppConfig.self, from: data)
    }
}
