import AppKit
import SwiftUI
import XCTest
@testable import Mousse

final class SettingsPreviewTests: XCTestCase {
    private final class PreviewSession: DeviceTrackingSession {
        func start() {}
        func stop() {}
    }

    @MainActor
    func testRenderIsolatedSettingsPreviewsWhenExplicitlyRequested() throws {
        guard let directory = ProcessInfo.processInfo.environment["MOUSSE_SETTINGS_PREVIEW_DIR"] else {
            throw XCTSkip("Set MOUSSE_SETTINGS_PREVIEW_DIR to render isolated source previews")
        }
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let temporary = repo.appendingPathComponent(".build/settings-preview-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let originalLanguage = Localized.language
        defer { Localized.language = originalLanguage }
        _ = NSApplication.shared // No AppDelegate, application launch, event tap or visible window.

        let languages: [(AppLanguage, String, String)] = [
            (.english, "en", "Example mouse"),
            (.simplifiedChinese, "zh", "示例鼠标"),
            (.japanese, "ja", "サンプルマウス"),
        ]
        for (language, suffix, name) in languages {
            for (tab, filename) in [(1, "buttons"), (2, "scroll"), (3, "pointer"), (5, "devices")] {
                try autoreleasepool {
                    var config = AppConfig()
                    config.enabled = false
                    config.language = language
                    config.scrollMode = .smoothStep
                    config.scrollSpeed = 0.8
                    config.scrollLines = 3
                    var settings = config.scrollSettings
                    settings.scrollMode = .smooth
                    config.deviceProfiles = [DeviceProfile(id: "046d:c548", name: name, settings: settings)]
                    let file = temporary.appendingPathComponent("\(filename)_\(suffix).json")
                    let fixture = try JSONEncoder().encode(config)
                    try fixture.write(to: file)
                    // Load a prewritten, disabled fixture: never assign store.config (live reload side effects).
                    let store = ConfigStore(fileURL: file)
                    let tracker = DeviceTracker(permission: { true }, automaticallyRetry: false) { _, _ in PreviewSession() }
                    // A fake background demand keeps example data stable while the offscreen probe hides its UI demand.
                    tracker.configure(enabled: true, hasProfiles: true)
                    defer { tracker.shutdown() }
                    tracker.publish([HIDDeviceInfo(key: "046d:c548", name: name)], from: tracker.currentSessionIdentity!)
                    let content = SettingsView(initialTab: tab, tracker: tracker)
                        .environmentObject(store)
                        .environment(\.locale, Locale(identifier: language.localeIdentifier))
                        .environment(\.colorScheme, .light)
                        .background(Color(nsColor: .windowBackgroundColor))
                    let host = NSHostingView(rootView: content)
                    host.frame = NSRect(x: 0, y: 0, width: 512, height: 512)
                    let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .closable],
                                          backing: .buffered, defer: false)
                    window.appearance = NSAppearance(named: .aqua)
                    host.appearance = NSAppearance(named: .aqua)
                    window.isReleasedWhenClosed = false
                    window.contentView = host
                    defer { window.contentView = nil; window.close() }
                    for _ in 0..<8 {
                        host.layoutSubtreeIfNeeded()
                        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.04))
                    }
                    host.displayIfNeeded()
                    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    XCTAssertGreaterThanOrEqual(bitmap.pixelsWide, 512)
                    XCTAssertGreaterThanOrEqual(bitmap.pixelsHigh, 512)
                    let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    XCTAssertGreaterThan(png.count, 10_000, "Blank/empty setting preview: \(filename)_\(suffix)")
                    try png.write(to: output.appendingPathComponent("\(filename)_\(suffix).png"), options: .atomic)
                    // Rendered views must not mutate the isolated config or queue a persistence write.
                    XCTAssertEqual(try Data(contentsOf: file), fixture)
                }
            }
        }
    }
}
