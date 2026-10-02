import XCTest
@testable import Mousse

final class ConfigStoreTests: XCTestCase {

    @MainActor
    func testCorruptBackupSitsNextToConfigWithTimestamp() {
        let config = URL(fileURLWithPath: "/tmp/Mousse/config.json")
        let date = Date(timeIntervalSince1970: 0)
        let backup = ConfigStore.corruptBackupURL(for: config, at: date)
        XCTAssertEqual(backup.deletingLastPathComponent().path, "/tmp/Mousse")
        XCTAssertEqual(backup.lastPathComponent, "config-corrupt-1970-01-01T00-00-00Z.json")
        XCTAssertFalse(backup.lastPathComponent.contains(":"))
    }

    @MainActor
    func testUnreadableConfigCannotDismissProtectionWithoutRetry() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mousse-config-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let configURL = root.appendingPathComponent("config.json")
        try FileManager.default.createDirectory(at: configURL, withIntermediateDirectories: true)
        let store = ConfigStore(fileURL: configURL)

        XCTAssertTrue(store.saveIsBlocked)
        XCTAssertNotNil(store.persistenceIssue)
        store.dismissPersistenceIssue()
        XCTAssertNotNil(store.persistenceIssue)
    }

    @MainActor
    func testExplicitRetryKeepsProtectionOnFailureAndClearsItOnSuccess() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mousse-config-retry-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let configURL = root.appendingPathComponent("config.json")
        try FileManager.default.createDirectory(at: configURL, withIntermediateDirectories: true)
        let marker = configURL.appendingPathComponent("keep.txt")
        let original = Data("unreadable original".utf8)
        try original.write(to: marker)
        let store = ConfigStore(fileURL: configURL)

        store.retrySave()
        XCTAssertTrue(store.saveIsBlocked)
        guard case .saveFailed = store.persistenceIssue else {
            return XCTFail("A failed explicit retry must surface the save failure")
        }
        store.dismissPersistenceIssue()
        XCTAssertNotNil(store.persistenceIssue)
        XCTAssertEqual(try Data(contentsOf: marker), original)

        // Remove only the test fixture obstruction; the store must still require explicit retry.
        try FileManager.default.removeItem(at: configURL)
        store.flushPendingSave()
        XCTAssertTrue(store.saveIsBlocked)
        XCTAssertFalse(FileManager.default.fileExists(atPath: configURL.path))
        store.retrySave()
        XCTAssertFalse(store.saveIsBlocked)
        XCTAssertNil(store.persistenceIssue)
        XCTAssertEqual(try JSONDecoder().decode(AppConfig.self, from: Data(contentsOf: configURL)),
                       store.config)
    }

    @MainActor
    func testCorruptConfigBackupPreservesOriginalBeforeExplicitRetry() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mousse-config-corrupt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let configURL = root.appendingPathComponent("config.json")
        let original = Data("{broken json".utf8)
        try original.write(to: configURL)
        let store = ConfigStore(fileURL: configURL)
        guard case .corruptConfigRecovered(let backupPath) = store.persistenceIssue else {
            return XCTFail("Corrupt JSON must be backed up before loading defaults")
        }
        let backup = URL(fileURLWithPath: try XCTUnwrap(backupPath))
        XCTAssertEqual(try Data(contentsOf: backup), original)
        XCTAssertEqual(try Data(contentsOf: configURL), original)
        XCTAssertFalse(store.saveIsBlocked)
        store.retrySave()
        XCTAssertNil(store.persistenceIssue)
        XCTAssertEqual(try JSONDecoder().decode(AppConfig.self, from: Data(contentsOf: configURL)),
                       store.config)
        XCTAssertEqual(try Data(contentsOf: backup), original)
    }

}
