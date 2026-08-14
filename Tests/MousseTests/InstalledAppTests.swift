import AppKit
import XCTest
@testable import Mousse

@MainActor
final class InstalledAppTests: XCTestCase {
    func testMissingApplicationLookupIsCached() {
        let bundleID = "com.mousse.tests.missing.\(UUID().uuidString)"
        var resolutions = 0
        let resolve: @MainActor (String) -> InstalledApp? = { _ in
            resolutions += 1
            return nil
        }

        XCTAssertNil(InstalledApp.lookup(bundleID, resolve: resolve))
        XCTAssertNil(InstalledApp.lookup(bundleID, resolve: resolve))
        XCTAssertEqual(resolutions, 1)
    }
}
