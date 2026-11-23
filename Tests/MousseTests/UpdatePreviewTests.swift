import AppKit
import SwiftUI
import XCTest
@testable import Mousse

/// Renders the update surfaces offscreen when `MOUSSE_UPDATE_PREVIEW_DIR` is set, so the menu
/// entry and the Settings row can be inspected without launching the app.
@MainActor
final class UpdatePreviewTests: XCTestCase {

    private final class PreviewSession: DeviceTrackingSession {
        func start() {}
        func stop() {}
    }

    private func releaseJSON(tag: String) -> Data {
        Data("""
        {"tag_name":"\(tag)","html_url":"https://github.com/Souitou-iop/Mousse/releases/tag/\(tag)",
         "body":"","draft":false,"prerelease":false,
         "assets":[{"name":"Mousse-arm64.zip","browser_download_url":"https://example.com/a.zip"},
                   {"name":"Mousse-x86_64.zip","browser_download_url":"https://example.com/x.zip"},
                   {"name":"SHA256SUMS","browser_download_url":"https://example.com/SHA256SUMS"}]}
        """.utf8)
    }

    private func checker(current: String, tag: String) -> UpdateChecker {
        let suite = "MousseTests.preview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return UpdateChecker(currentVersion: current, defaults: defaults) { _ in
            (self.releaseJSON(tag: tag), HTTPURLResponse(
                url: URL(string: "https://api.github.com")!, statusCode: 200,
                httpVersion: nil, headerFields: nil)!)
        }
    }

    private func render<V: View>(_ view: V, size: NSSize, to url: URL) throws {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        host.appearance = NSAppearance(named: .aqua)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        for _ in 0..<10 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        host.displayIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: url, options: .atomic)
    }

    private func makeStore(_ language: AppLanguage) throws -> (ConfigStore, URL) {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mousse-update-preview-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var config = AppConfig()
        config.enabled = false
        config.language = language
        let file = directory.appendingPathComponent("config.json")
        try JSONEncoder().encode(config).write(to: file)
        return (ConfigStore(fileURL: file), directory)
    }

    func testRenderUpdateSurfaces() async throws {
        guard let directory = ProcessInfo.processInfo.environment["MOUSSE_UPDATE_PREVIEW_DIR"] else {
            throw XCTSkip("Set MOUSSE_UPDATE_PREVIEW_DIR to render update-surface previews")
        }
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        _ = NSApplication.shared
        let originalLanguage = Localized.language
        defer { Localized.language = originalLanguage }

        for (language, suffix) in [(AppLanguage.english, "en"), (.simplifiedChinese, "zh")] {
            Localized.language = language
            let (store, temp) = try makeStore(language)
            defer { try? FileManager.default.removeItem(at: temp) }

            let available = checker(current: "0.30.0", tag: "v0.31.0")
            await available.check()
            XCTAssertNotNil(available.phase.availableRelease)

            try autoreleasepool {
                try render(MenuContent(updates: available).environmentObject(store),
                           size: NSSize(width: 260, height: 320),
                           to: output.appendingPathComponent("menu-available_\(suffix).png"))
            }

            let upToDate = checker(current: "0.31.0", tag: "v0.31.0")
            await upToDate.check()
            XCTAssertEqual(upToDate.phase, .upToDate(current: "0.31.0"))

            try autoreleasepool {
                try render(MenuContent(updates: upToDate).environmentObject(store),
                           size: NSSize(width: 260, height: 320),
                           to: output.appendingPathComponent("menu-uptodate_\(suffix).png"))
            }

            let tracker = DeviceTracker(permission: { true }, automaticallyRetry: false) { _, _ in PreviewSession() }
            defer { tracker.shutdown() }
            try autoreleasepool {
                try render(SettingsView(initialTab: 0, tracker: tracker, updates: available)
                                .environmentObject(store)
                                .environment(\.locale, Locale(identifier: language.localeIdentifier)),
                           size: NSSize(width: 560, height: 600),
                           to: output.appendingPathComponent("settings-update_\(suffix).png"))
            }
        }
    }
}
