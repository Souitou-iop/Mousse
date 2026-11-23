import AppKit
import Combine
import CryptoKit
import Foundation

/// A dotted numeric version ("v0.31.0" → [0, 31]). Trailing zeros are trimmed so `0.31` and
/// `0.31.0` compare equal; anything after the numeric core (a pre-release suffix) is ignored —
/// the update feed only serves stable releases.
struct AppVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
    let components: [Int]

    init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        let core = text.prefix { $0.isNumber || $0 == "." }
        guard !core.isEmpty else { return nil }
        var numbers: [Int] = []
        for part in core.split(separator: ".", omittingEmptySubsequences: false) {
            guard let value = Int(part), value >= 0 else { return nil }
            numbers.append(value)
        }
        guard !numbers.isEmpty else { return nil }
        while numbers.count > 1, numbers.last == 0 { numbers.removeLast() }
        components = numbers
    }

    var description: String { components.map(String.init).joined(separator: ".") }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

/// One downloadable file of a GitHub release.
struct ReleaseAsset: Equatable, Sendable {
    let name: String
    let url: URL
}

/// A published stable release, decoded from the GitHub Releases API.
struct ReleaseInfo: Equatable, Sendable {
    let version: String      // tag without the leading "v", e.g. "0.32.0"
    let tag: String          // as published, e.g. "v0.32.0"
    let htmlURL: URL
    let notes: String
    let assets: [ReleaseAsset]

    var parsedVersion: AppVersion? { AppVersion(version) }

    /// The archive matching the running slice. Both packages carry the bundle as `Mousse.app`,
    /// so the caller never renames anything after unzipping.
    func asset(for architecture: UpdateArchitecture) -> ReleaseAsset? {
        assets.first { $0.name == architecture.archiveName }
    }

    func checksumAsset() -> ReleaseAsset? {
        assets.first { $0.name == "SHA256SUMS" }
    }
}

/// The architecture this build should update with — the slice the binary was compiled for, which
/// is exactly what `build-app.sh` produced.
enum UpdateArchitecture: String, Sendable {
    case arm64
    case x86_64

    static var current: UpdateArchitecture {
        #if arch(arm64)
        return .arm64
        #else
        return .x86_64
        #endif
    }

    var archiveName: String { "Mousse-\(rawValue).zip" }
}

/// Parses a `SHA256SUMS` file ("<hex>  <name>", one per line) into a name → hex digest map.
enum ChecksumManifest {
    static func parse(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 2 else { continue }
            let digest = String(parts[0]).lowercased()
            // `shasum` writes two spaces, and some tools prefix the name with "*".
            let name = String(parts[1]).trimmingCharacters(in: CharacterSet(charactersIn: "*"))
            guard digest.count == 64 else { continue }
            result[name] = digest
        }
        return result
    }

    static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Checks GitHub Releases for a newer build and, on request, downloads the matching archive.
///
/// Deliberately not Sparkle: the app ships as a plain signed bundle built by `build-app.sh`, and
/// an embedded updater framework would need its own XPC services and appcast. The release feed
/// already publishes per-architecture archives plus `SHA256SUMS`, so detection is one JSON
/// request and a download can be verified against the same manifest.
@MainActor
final class UpdateChecker: ObservableObject {

    enum Phase: Equatable {
        case idle
        case checking
        case upToDate(current: String)
        case available(ReleaseInfo)
        case failed(String)

        var availableRelease: ReleaseInfo? {
            if case .available(let release) = self { return release }
            return nil
        }

        var isChecking: Bool { self == .checking }
    }

    enum DownloadState: Equatable {
        case idle
        case downloading
        case saved(URL)
        case failed(String)
    }

    static let shared = UpdateChecker()

    /// Public repository that publishes the release feed.
    static let repository = "Souitou-iop/Mousse"
    private static let lastCheckKey = "Mousse.lastUpdateCheck"
    private static let automaticInterval: TimeInterval = 24 * 60 * 60
    private static let launchDelay: TimeInterval = 10

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var downloadState: DownloadState = .idle

    private let currentVersionOverride: String?
    private let fetch: (URLRequest) async throws -> (Data, URLResponse)
    private let fileManager: FileManager
    private let defaults: UserDefaults
    private let downloadsDirectory: URL?
    private var automaticTimer: Timer?
    private var checkTask: Task<Phase, Never>?
    private var downloadTask: Task<Void, Never>?

    var currentVersion: String {
        currentVersionOverride
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0"
    }

    init(currentVersion: String? = nil,
         defaults: UserDefaults = .standard,
         fileManager: FileManager = .default,
         downloadsDirectory: URL? = nil,
         fetch: ((URLRequest) async throws -> (Data, URLResponse))? = nil) {
        self.currentVersionOverride = currentVersion
        self.defaults = defaults
        self.fileManager = fileManager
        self.downloadsDirectory = downloadsDirectory
        self.fetch = fetch ?? { request in try await URLSession.shared.data(for: request) }
    }

    var releasesAPIURL: URL {
        URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!
    }

    // MARK: Scheduling

    /// Starts automatic checks when enabled: one shortly after launch (so the app's own startup
    /// is never competing with the network) and then once a day. Idempotent.
    func startAutomaticChecks(enabled: Bool) {
        automaticTimer?.invalidate()
        automaticTimer = nil
        guard enabled else { return }
        let elapsed = Date().timeIntervalSince(lastCheckDate ?? .distantPast)
        let delay = elapsed >= Self.automaticInterval ? Self.launchDelay : Self.automaticInterval - elapsed
        schedule(after: delay)
    }

    private func schedule(after delay: TimeInterval) {
        automaticTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                await self.check()
                self.schedule(after: Self.automaticInterval)
            }
        }
    }

    private var lastCheckDate: Date? {
        defaults.object(forKey: Self.lastCheckKey) as? Date
    }

    // MARK: Checking

    /// One check. Returns the resulting phase so tests can await it without observing Combine.
    @discardableResult
    func check() async -> Phase {
        if let existing = checkTask { return await existing.value }
        let task = Task { await self.performCheck() }
        checkTask = task
        let result = await task.value
        checkTask = nil
        return result
    }

    private func performCheck() async -> Phase {
        phase = .checking
        let result = await resolvePhase()
        phase = result
        // Only a conclusive answer counts as "checked": a transient network failure must not
        // suppress the next automatic attempt for a full day.
        if case .failed = result { return result }
        defaults.set(Date(), forKey: Self.lastCheckKey)
        return result
    }

    private func resolvePhase() async -> Phase {
        do {
            var request = URLRequest(url: releasesAPIURL)
            request.timeoutInterval = 20
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Mousse/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await fetch(request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return .failed("HTTP \(http.statusCode)")
            }
            let release = try Self.decodeRelease(data)
            if let current = AppVersion(currentVersion),
               let latest = release.parsedVersion,
               latest > current {
                return .available(release)
            }
            return .upToDate(current: currentVersion)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Decodes the subset of the GitHub release payload the checker needs. Drafts and
    /// pre-releases never reach `/releases/latest`, but are rejected here anyway so a future
    /// switch to `/releases` cannot offer a beta as an update.
    nonisolated static func decodeRelease(_ data: Data) throws -> ReleaseInfo {
        struct Payload: Decodable {
            struct Asset: Decodable {
                let name: String
                let browserDownloadURL: URL
                enum CodingKeys: String, CodingKey {
                    case name
                    case browserDownloadURL = "browser_download_url"
                }
            }
            let tagName: String
            let htmlURL: URL
            let body: String?
            let draft: Bool
            let prerelease: Bool
            let assets: [Asset]
            enum CodingKeys: String, CodingKey {
                case tagName = "tag_name"
                case htmlURL = "html_url"
                case body, draft, prerelease, assets
            }
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard !payload.draft, !payload.prerelease else {
            throw UpdateError.notAStableRelease
        }
        let version = payload.tagName.hasPrefix("v")
            ? String(payload.tagName.dropFirst())
            : payload.tagName
        guard AppVersion(version) != nil else { throw UpdateError.unreadableVersion(payload.tagName) }
        return ReleaseInfo(version: version,
                           tag: payload.tagName,
                           htmlURL: payload.htmlURL,
                           notes: payload.body ?? "",
                           assets: payload.assets.map { ReleaseAsset(name: $0.name, url: $0.browserDownloadURL) })
    }

    // MARK: Downloading

    /// Downloads the archive for this build's architecture, verifies it against the release's
    /// `SHA256SUMS`, unpacks it into `~/Downloads/Mousse-<version>` and reveals the bundle.
    /// It never replaces a running app: the user moves it into place themselves, which keeps the
    /// app's location (and any launcher/symlink setup) under their control.
    func download(_ release: ReleaseInfo) {
        guard downloadTask == nil else { return }
        downloadState = .downloading
        downloadTask = Task {
            defer { downloadTask = nil }
            do {
                let architecture = UpdateArchitecture.current
                guard let archive = release.asset(for: architecture) else {
                    throw UpdateError.missingAsset(architecture.archiveName)
                }
                guard let checksumAsset = release.checksumAsset() else {
                    throw UpdateError.missingAsset("SHA256SUMS")
                }
                let manifestData = try await downloadData(checksumAsset.url)
                guard let expected = ChecksumManifest
                    .parse(String(decoding: manifestData, as: UTF8.self))[archive.name] else {
                    throw UpdateError.checksumMissing(archive.name)
                }
                let archiveData = try await downloadData(archive.url)
                guard ChecksumManifest.sha256(of: archiveData) == expected else {
                    throw UpdateError.checksumMismatch(archive.name)
                }
                let destination = try unpack(archiveData, version: release.version)
                downloadState = .saved(destination)
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch {
                downloadState = .failed(error.localizedDescription)
            }
        }
    }

    private func downloadData(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        request.setValue("Mousse/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await fetch(request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UpdateError.downloadFailed("HTTP \(http.statusCode)")
        }
        return data
    }

    /// Unpacks into a fresh per-version folder in Downloads and returns the extracted bundle.
    private func unpack(_ archive: Data, version: String) throws -> URL {
        let downloads = downloadsDirectory
            ?? fileManager.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let folder = downloads.appendingPathComponent("Mousse-\(version)", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let zipURL = folder.appendingPathComponent("Mousse.zip")
        try archive.write(to: zipURL, options: .atomic)
        defer { try? fileManager.removeItem(at: zipURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zipURL.path, folder.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.unpackFailed
        }
        let bundle = folder.appendingPathComponent("Mousse.app", isDirectory: true)
        guard fileManager.fileExists(atPath: bundle.path) else { throw UpdateError.unpackFailed }
        return bundle
    }
}

enum UpdateError: LocalizedError {
    case notAStableRelease
    case unreadableVersion(String)
    case missingAsset(String)
    case checksumMissing(String)
    case checksumMismatch(String)
    case downloadFailed(String)
    case unpackFailed

    var errorDescription: String? {
        switch self {
        case .notAStableRelease: return "latest release is not stable"
        case .unreadableVersion(let tag): return "unreadable version tag: \(tag)"
        case .missingAsset(let name): return "release is missing \(name)"
        case .checksumMissing(let name): return "SHA256SUMS has no entry for \(name)"
        case .checksumMismatch(let name): return "checksum mismatch for \(name)"
        case .downloadFailed(let reason): return "download failed: \(reason)"
        case .unpackFailed: return "could not unpack the downloaded archive"
        }
    }
}
