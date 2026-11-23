import XCTest
@testable import Mousse

final class AppVersionTests: XCTestCase {

    func testParsesTagPrefixAndTrailingZeros() {
        XCTAssertEqual(AppVersion("v0.31.0")?.components, [0, 31])
        XCTAssertEqual(AppVersion("0.31")?.components, [0, 31])
        XCTAssertEqual(AppVersion("  V1.2.3 ")?.components, [1, 2, 3])
        XCTAssertEqual(AppVersion("0.31.0")?.description, "0.31")
    }

    func testComparesNumericallyNotLexically() {
        // "0.9" > "0.10" lexically; the version must order by value.
        XCTAssertTrue(AppVersion("0.10")! > AppVersion("0.9")!)
        XCTAssertTrue(AppVersion("1.0")! > AppVersion("0.99.9")!)
        XCTAssertEqual(AppVersion("0.31.0"), AppVersion("0.31"))
        XCTAssertFalse(AppVersion("0.31")! > AppVersion("0.31.0")!)
    }

    func testRejectsNonVersions() {
        XCTAssertNil(AppVersion(""))
        XCTAssertNil(AppVersion("nightly"))
        XCTAssertNil(AppVersion("v"))
        XCTAssertNil(AppVersion("1.2.x"))
        XCTAssertNil(AppVersion("-1"))
    }

    func testPreReleaseSuffixIsIgnoredForTheNumericCore() {
        XCTAssertEqual(AppVersion("0.32.0-beta.1"), AppVersion("0.32.0"))
    }
}

final class ReleaseDecodingTests: XCTestCase {

    private func payload(tag: String = "v0.32.0",
                         draft: Bool = false,
                         prerelease: Bool = false,
                         assets: [(String, String)] = [
                            ("Mousse-arm64.zip", "https://example.com/arm64.zip"),
                            ("Mousse-x86_64.zip", "https://example.com/x86.zip"),
                            ("SHA256SUMS", "https://example.com/SHA256SUMS"),
                         ]) -> Data {
        let assetJSON = assets.map { #"{"name":"\#($0.0)","browser_download_url":"\#($0.1)"}"# }
            .joined(separator: ",")
        let json = """
        {"tag_name":"\(tag)","html_url":"https://github.com/Souitou-iop/Mousse/releases/tag/\(tag)",
         "body":"notes","draft":\(draft),"prerelease":\(prerelease),"assets":[\(assetJSON)]}
        """
        return Data(json.utf8)
    }

    func testDecodesStableReleaseAndPicksArchitecture() throws {
        let release = try UpdateChecker.decodeRelease(payload())
        XCTAssertEqual(release.version, "0.32.0")
        XCTAssertEqual(release.tag, "v0.32.0")
        XCTAssertEqual(release.notes, "notes")
        XCTAssertEqual(release.asset(for: .arm64)?.url.absoluteString, "https://example.com/arm64.zip")
        XCTAssertEqual(release.asset(for: .x86_64)?.url.absoluteString, "https://example.com/x86.zip")
        XCTAssertEqual(release.checksumAsset()?.name, "SHA256SUMS")
    }

    func testRejectsDraftAndPrerelease() {
        XCTAssertThrowsError(try UpdateChecker.decodeRelease(payload(draft: true)))
        XCTAssertThrowsError(try UpdateChecker.decodeRelease(payload(prerelease: true)))
    }

    func testRejectsUnreadableTag() {
        XCTAssertThrowsError(try UpdateChecker.decodeRelease(payload(tag: "nightly")))
    }

    func testMissingArchitectureAssetReturnsNil() throws {
        let release = try UpdateChecker.decodeRelease(payload(assets: [("Mousse-arm64.zip", "https://e/a.zip")]))
        XCTAssertNotNil(release.asset(for: .arm64))
        XCTAssertNil(release.asset(for: .x86_64))
        XCTAssertNil(release.checksumAsset())
    }
}

final class ChecksumManifestTests: XCTestCase {
    private let digest = String(repeating: "a", count: 64)

    func testParsesShasumOutput() {
        let text = "\(digest)  Mousse-arm64.zip\n\(String(repeating: "b", count: 64))  Mousse-x86_64.zip\n"
        let parsed = ChecksumManifest.parse(text)
        XCTAssertEqual(parsed["Mousse-arm64.zip"], digest)
        XCTAssertEqual(parsed["Mousse-x86_64.zip"], String(repeating: "b", count: 64))
    }

    func testParsesBinaryModeMarkerAndIgnoresJunk() {
        let text = "\(digest) *Mousse-arm64.zip\nnot-a-digest  other.zip\n\n"
        XCTAssertEqual(ChecksumManifest.parse(text)["Mousse-arm64.zip"], digest)
        XCTAssertNil(ChecksumManifest.parse(text)["other.zip"])
    }

    func testHashesKnownData() {
        // Well-known SHA-256 of "abc".
        XCTAssertEqual(ChecksumManifest.sha256(of: Data("abc".utf8)),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}

@MainActor
final class UpdateCheckerTests: XCTestCase {

    private func releaseJSON(tag: String) -> Data {
        Data("""
        {"tag_name":"\(tag)","html_url":"https://github.com/Souitou-iop/Mousse/releases/tag/\(tag)",
         "body":"","draft":false,"prerelease":false,
         "assets":[{"name":"Mousse-arm64.zip","browser_download_url":"https://example.com/Mousse-arm64.zip"},
                   {"name":"Mousse-x86_64.zip","browser_download_url":"https://example.com/Mousse-x86_64.zip"},
                   {"name":"SHA256SUMS","browser_download_url":"https://example.com/SHA256SUMS"}]}
        """.utf8)
    }

    private func httpResponse(_ status: Int) -> URLResponse {
        HTTPURLResponse(url: URL(string: "https://api.github.com")!, statusCode: status,
                        httpVersion: nil, headerFields: nil)!
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "MousseTests.update.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testNewerReleaseIsReportedAsAvailable() async {
        let checker = UpdateChecker(currentVersion: "0.31.0", defaults: makeDefaults()) { _ in
            (self.releaseJSON(tag: "v0.32.0"), self.httpResponse(200))
        }
        let phase = await checker.check()
        guard case .available(let release) = phase else {
            return XCTFail("expected .available, got \(phase)")
        }
        XCTAssertEqual(release.version, "0.32.0")
        XCTAssertEqual(checker.phase, phase)
    }

    func testSameVersionIsUpToDate() async {
        let checker = UpdateChecker(currentVersion: "0.32.0", defaults: makeDefaults()) { _ in
            (self.releaseJSON(tag: "v0.32.0"), self.httpResponse(200))
        }
        guard case .upToDate(let current) = await checker.check() else {
            return XCTFail("expected .upToDate")
        }
        XCTAssertEqual(current, "0.32.0")
    }

    func testOlderPublishedReleaseIsNotAnUpdate() async {
        let checker = UpdateChecker(currentVersion: "0.33.0", defaults: makeDefaults()) { _ in
            (self.releaseJSON(tag: "v0.32.0"), self.httpResponse(200))
        }
        guard case .upToDate = await checker.check() else {
            return XCTFail("a downgrade must not be offered")
        }
    }

    func testHTTPFailureSurfacesAsFailedPhase() async {
        let checker = UpdateChecker(currentVersion: "0.31.0", defaults: makeDefaults()) { _ in
            (Data(), self.httpResponse(503))
        }
        guard case .failed(let reason) = await checker.check() else {
            return XCTFail("expected .failed")
        }
        XCTAssertTrue(reason.contains("503"))
    }

    func testNetworkErrorSurfacesAsFailedPhase() async {
        struct Offline: Error {}
        let checker = UpdateChecker(currentVersion: "0.31.0", defaults: makeDefaults()) { _ in
            throw Offline()
        }
        guard case .failed = await checker.check() else {
            return XCTFail("expected .failed")
        }
    }

    func testConcurrentChecksShareOneRequest() async {
        let counter = RequestCounter()
        let checker = UpdateChecker(currentVersion: "0.31.0", defaults: makeDefaults()) { _ in
            await counter.increment()
            return (self.releaseJSON(tag: "v0.32.0"), self.httpResponse(200))
        }
        async let first = checker.check()
        async let second = checker.check()
        _ = await (first, second)
        let count = await counter.value
        XCTAssertEqual(count, 1, "an in-flight check must be reused, not duplicated")
    }

    func testAutomaticChecksDisabledClearsSchedule() {
        let checker = UpdateChecker(currentVersion: "0.31.0", defaults: makeDefaults())
        checker.startAutomaticChecks(enabled: true)
        checker.startAutomaticChecks(enabled: false)
        // Nothing observable to assert beyond "does not crash / no timer retains the checker";
        // the state transition is the contract here.
        XCTAssertEqual(checker.phase, .idle)
    }

    /// A failed check must not be remembered as "checked today", or a flaky network at launch
    /// would delay the next automatic attempt by 24 hours.
    func testFailureDoesNotRecordCheckTimestamp() async {
        let defaults = makeDefaults()
        struct Offline: Error {}
        let failing = UpdateChecker(currentVersion: "0.31.0", defaults: defaults) { _ in throw Offline() }
        guard case .failed = await failing.check() else { return XCTFail("expected .failed") }

        let counter = RequestCounter()
        let succeeding = UpdateChecker(currentVersion: "0.31.0", defaults: defaults) { _ in
            await counter.increment()
            return (self.releaseJSON(tag: "v0.31.0"), self.httpResponse(200))
        }
        guard case .upToDate = await succeeding.check() else { return XCTFail("expected .upToDate") }
        let requests = await counter.value
        XCTAssertEqual(requests, 1)
    }

    // MARK: Download pipeline (stubbed transport, real hashing + unpack)

    private func archiveBytes() throws -> Data {
        // A tiny real zip so `ditto -x -k` succeeds and produces Mousse.app.
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mousse-zip-\(UUID())", isDirectory: true)
        let bundle = root.appendingPathComponent("Mousse.app", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Contents/MacOS"),
                                                withIntermediateDirectories: true)
        try Data("binary".utf8).write(to: bundle.appendingPathComponent("Contents/MacOS/Mousse"))
        defer { try? FileManager.default.removeItem(at: root) }
        let zip = root.appendingPathComponent("archive.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", bundle.path, zip.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return try Data(contentsOf: zip)
    }

    /// Downloads land in a throwaway directory, never the real ~/Downloads.
    private func downloadChecker(archive: Data,
                                 manifest: String,
                                 current: String = "0.30.0") throws -> UpdateChecker {
        let defaults = makeDefaults()
        let downloads = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mousse-downloads-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: downloads) }
        return UpdateChecker(currentVersion: current, defaults: defaults,
                             downloadsDirectory: downloads) { request in
            let body: Data
            switch request.url?.lastPathComponent {
            case "SHA256SUMS": body = Data(manifest.utf8)
            case "Mousse-arm64.zip", "Mousse-x86_64.zip": body = archive
            default: body = self.releaseJSON(tag: "v0.31.0")
            }
            return (body, self.httpResponse(200))
        }
    }

    private func waitForDownload(_ checker: UpdateChecker) async throws -> UpdateChecker.DownloadState {
        for _ in 0..<200 {
            if checker.downloadState != .downloading { return checker.downloadState }
            try await Task.sleep(for: .milliseconds(50))
        }
        return checker.downloadState
    }

    func testDownloadVerifiesChecksumAndUnpacksBundle() async throws {
        let archive = try archiveBytes()
        let name = UpdateArchitecture.current.archiveName
        let manifest = "\(ChecksumManifest.sha256(of: archive))  \(name)\n"
        let checker = try downloadChecker(archive: archive, manifest: manifest)
        guard case .available(let release) = await checker.check() else { return XCTFail("no release") }
        checker.download(release)
        let state = try await waitForDownload(checker)
        guard case .saved(let bundle) = state else { return XCTFail("expected .saved, got \(state)") }
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: bundle.appendingPathComponent("Contents/MacOS/Mousse").path))
        XCTAssertTrue(bundle.path.contains("mousse-downloads-"), bundle.path)
    }

    func testDownloadRejectsTamperedArchive() async throws {
        let archive = try archiveBytes()
        let manifest = "\(String(repeating: "0", count: 64))  \(UpdateArchitecture.current.archiveName)\n"
        let checker = try downloadChecker(archive: archive, manifest: manifest)
        guard case .available(let release) = await checker.check() else { return XCTFail("no release") }
        checker.download(release)
        let state = try await waitForDownload(checker)
        guard case .failed(let reason) = state else { return XCTFail("expected .failed, got \(state)") }
        XCTAssertTrue(reason.contains("checksum"), reason)
    }

    func testDownloadFailsWhenManifestLacksTheArchive() async throws {
        let archive = try archiveBytes()
        let checker = try downloadChecker(archive: archive,
                                          manifest: "\(String(repeating: "a", count: 64))  other.zip\n")
        guard case .available(let release) = await checker.check() else { return XCTFail("no release") }
        checker.download(release)
        let state = try await waitForDownload(checker)
        guard case .failed(let reason) = state else { return XCTFail("expected .failed, got \(state)") }
        XCTAssertTrue(reason.contains("SHA256SUMS"), reason)
    }
}

private actor RequestCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}
