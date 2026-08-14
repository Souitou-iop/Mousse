import CoreGraphics
import XCTest
@testable import Mousse

final class SmartNavigationTests: XCTestCase {
    func testPostingIsDeferredToMainQueue() {
        let posted = expectation(description: "navigation dispatches asynchronously")

        DispatchQueue.global().async {
            SmartNavigation.dispatchOnMain {
                XCTAssertTrue(Thread.isMainThread)
                posted.fulfill()
            }
        }

        wait(for: [posted], timeout: 1)
    }

    func testFinderUsesNativeHistoryCommands() {
        XCTAssertEqual(SmartNavigation.strategy(for: "com.apple.finder"), .commandBracket)
    }

    func testSafariUsesNativeHistoryCommands() {
        XCTAssertEqual(SmartNavigation.strategy(for: "com.apple.Safari"), .commandBracket)
    }

    func testNavigationTargetFallsBackToFrontmostApplication() {
        XCTAssertEqual(
            SmartNavigation.navigationTarget(windowBundleID: nil,
                                             frontmostBundleID: "com.apple.finder"),
            "com.apple.finder")
        XCTAssertEqual(
            SmartNavigation.navigationTarget(windowBundleID: "com.microsoft.edgemac",
                                             frontmostBundleID: "com.apple.finder"),
            "com.microsoft.edgemac")
    }

    func testOtherCompatibleAppsUseNavigationSwipe() {
        XCTAssertEqual(SmartNavigation.strategy(for: "com.apple.Music"), .navigationSwipe)
        XCTAssertEqual(SmartNavigation.strategy(for: "com.operasoftware.Opera"), .navigationSwipe)
        XCTAssertEqual(SmartNavigation.strategy(for: "com.binarynights.ForkLift"), .navigationSwipe)
    }

    func testChromiumAndUnknownAppsUseMouseButtons() {
        XCTAssertEqual(SmartNavigation.strategy(for: "com.microsoft.edgemac"), .mouseButton)
        XCTAssertEqual(SmartNavigation.strategy(for: "com.google.Chrome"), .mouseButton)
        XCTAssertEqual(SmartNavigation.strategy(for: nil), .mouseButton)
    }

    func testSyntheticMouseButtonsAreTaggedAndNumbered() {
        let back = SmartNavigation.makeMouseButtonEvents(.back, location: CGPoint(x: 10, y: 20))
        XCTAssertEqual(back.count, 2)
        XCTAssertEqual(back.map { $0.getIntegerValueField(.eventSourceUserData) },
                       [SmartNavigation.syntheticTag, SmartNavigation.syntheticTag])
        XCTAssertEqual(back.map { $0.getIntegerValueField(.mouseEventButtonNumber) }, [3, 3])
        XCTAssertEqual(back.map { $0.getIntegerValueField(.mouseEventClickState) }, [1, 1])
        XCTAssertEqual(back.map(\.type), [.otherMouseDown, .otherMouseUp])

        let forward = SmartNavigation.makeMouseButtonEvents(.forward, location: CGPoint(x: 10, y: 20))
        XCTAssertEqual(forward.map { $0.getIntegerValueField(.mouseEventButtonNumber) }, [4, 4])
    }

    func testNavigationSwipeUsesMMFEventFields() throws {
        let back = try XCTUnwrap(SmartNavigation.makeNavigationSwipeEvent(.back))
        XCTAssertEqual(back.getIntegerValueField(CGEventField(rawValue: 55)!), 29)
        XCTAssertEqual(back.getIntegerValueField(CGEventField(rawValue: 110)!), 6)
        XCTAssertEqual(back.getIntegerValueField(CGEventField(rawValue: 132)!), 1)
        XCTAssertEqual(back.getIntegerValueField(CGEventField(rawValue: 115)!), 4)
        XCTAssertEqual(back.getIntegerValueField(.eventSourceUserData), 0)

        SmartNavigation.finishNavigationSwipeEvent(back)
        XCTAssertEqual(back.getIntegerValueField(CGEventField(rawValue: 132)!), 4)
        XCTAssertEqual(back.getIntegerValueField(CGEventField(rawValue: 115)!), 0)

        let forward = try XCTUnwrap(SmartNavigation.makeNavigationSwipeEvent(.forward))
        XCTAssertEqual(forward.getIntegerValueField(CGEventField(rawValue: 115)!), 8)
    }
}
