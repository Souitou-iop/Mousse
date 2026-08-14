import XCTest
@testable import Mousse

final class ButtonTriggerRecognizerTests: XCTestCase {
    private let click = RemapAction.spaceLeft
    private let doubleClick = RemapAction.spaceRight
    private let hold = RemapAction.missionControl

    private func recognizer() -> ButtonTriggerRecognizer {
        let result = ButtonTriggerRecognizer()
        result.doubleClickInterval = 0.26
        result.holdDuration = 0.50
        return result
    }

    func testClickWithoutCompetingTriggersFiresOnPress() {
        let r = recognizer()
        let output = r.buttonDown(4, at: 1, actions: .init(click: click))
        XCTAssertEqual(output.triggered.map(\.action), [click])
    }

    func testIsTrackingFollowsDownAndUp() {
        let r = recognizer()
        XCTAssertFalse(r.isTracking(4))
        _ = r.buttonDown(4, at: 1, actions: .init(click: click))
        XCTAssertTrue(r.isTracking(4))
        _ = r.buttonUp(4, at: 1.1)
        XCTAssertFalse(r.isTracking(4))
    }

    func testClickWaitsWhenDoubleClickExists() {
        let r = recognizer()
        let actions = ButtonTriggerRecognizer.Actions(click: click, doubleClick: doubleClick)
        XCTAssertTrue(r.buttonDown(4, at: 1, actions: actions).triggered.isEmpty)
        XCTAssertTrue(r.buttonUp(4, at: 1.05).triggered.isEmpty)
        XCTAssertEqual(r.advance(to: 1.26).triggered.map(\.action), [click])
    }

    func testSecondPressWithinWindowFiresDoubleClickAndCancelsClick() {
        let r = recognizer()
        let actions = ButtonTriggerRecognizer.Actions(click: click, doubleClick: doubleClick)
        _ = r.buttonDown(4, at: 1, actions: actions)
        _ = r.buttonUp(4, at: 1.05)
        let second = r.buttonDown(4, at: 1.20, actions: actions)
        XCTAssertEqual(second.triggered.map(\.action), [doubleClick])
        XCTAssertTrue(r.advance(to: 2).triggered.isEmpty)
    }

    func testLateSecondPressStartsANewClickCycle() {
        let r = recognizer()
        let actions = ButtonTriggerRecognizer.Actions(click: click, doubleClick: doubleClick)
        _ = r.buttonDown(4, at: 1, actions: actions)
        _ = r.buttonUp(4, at: 1.05)
        let late = r.buttonDown(4, at: 1.30, actions: actions)
        XCTAssertEqual(late.triggered.map(\.action), [click])
        _ = r.buttonUp(4, at: 1.35)
        XCTAssertEqual(r.advance(to: 1.56).triggered.map(\.action), [click])
    }

    func testHoldFiresOnceAndSuppressesClick() {
        let r = recognizer()
        let actions = ButtonTriggerRecognizer.Actions(click: click, hold: hold)
        _ = r.buttonDown(4, at: 1, actions: actions)
        XCTAssertTrue(r.advance(to: 1.49).triggered.isEmpty)
        XCTAssertEqual(r.advance(to: 1.50).triggered.map(\.action), [hold])
        XCTAssertTrue(r.buttonUp(4, at: 1.75).triggered.isEmpty)
    }

    func testReleaseBeforeHoldFiresClick() {
        let r = recognizer()
        let actions = ButtonTriggerRecognizer.Actions(click: click, hold: hold)
        _ = r.buttonDown(4, at: 1, actions: actions)
        XCTAssertEqual(r.buttonUp(4, at: 1.20).triggered.map(\.action), [click])
    }

    func testHoldOnlyDoesNothingWhenReleasedEarly() {
        let r = recognizer()
        _ = r.buttonDown(4, at: 1, actions: .init(hold: hold))
        XCTAssertTrue(r.buttonUp(4, at: 1.20).triggered.isEmpty)
        XCTAssertTrue(r.advance(to: 2).triggered.isEmpty)
    }

    func testDoubleClickOnlyDoesNothingAfterSingleClickTimeout() {
        let r = recognizer()
        let actions = ButtonTriggerRecognizer.Actions(doubleClick: doubleClick)
        _ = r.buttonDown(4, at: 1, actions: actions)
        _ = r.buttonUp(4, at: 1.05)
        XCTAssertTrue(r.advance(to: 1.26).triggered.isEmpty)
        XCTAssertNil(r.nextDeadline)
    }

    func testThreeTriggersResolveToDoubleClickBeforeHold() {
        let r = recognizer()
        let actions = ButtonTriggerRecognizer.Actions(click: click, doubleClick: doubleClick,
                                                       hold: hold)
        _ = r.buttonDown(4, at: 1, actions: actions)
        _ = r.buttonUp(4, at: 1.10)
        XCTAssertEqual(r.buttonDown(4, at: 1.20, actions: actions).triggered.map(\.action),
                       [doubleClick])
        XCTAssertTrue(r.advance(to: 2).triggered.isEmpty)
    }

    func testButtonsMaintainIndependentCycles() {
        let r = recognizer()
        let actions = ButtonTriggerRecognizer.Actions(click: click, doubleClick: doubleClick)
        _ = r.buttonDown(4, at: 1, actions: actions)
        _ = r.buttonUp(4, at: 1.05)
        _ = r.buttonDown(5, at: 1.10, actions: actions)
        _ = r.buttonUp(5, at: 1.15)
        XCTAssertEqual(r.advance(to: 1.26).triggered.map(\.button), [4])
        XCTAssertEqual(r.advance(to: 1.36).triggered.map(\.button), [5])
    }

    func testCancelPreventsPendingActions() {
        let r = recognizer()
        let actions = ButtonTriggerRecognizer.Actions(click: click, doubleClick: doubleClick,
                                                       hold: hold)
        _ = r.buttonDown(4, at: 1, actions: actions)
        r.cancel(button: 4)
        XCTAssertTrue(r.advance(to: 2).triggered.isEmpty)

        _ = r.buttonDown(5, at: 3, actions: actions)
        r.cancelAll()
        XCTAssertTrue(r.advance(to: 4).triggered.isEmpty)
        XCTAssertNil(r.nextDeadline)
    }

    func testDeferredImmediateClickFiresOnReleaseForDragCandidate() {
        let r = recognizer()
        let actions = ButtonTriggerRecognizer.Actions(click: click)
        XCTAssertTrue(r.buttonDown(4, at: 1, actions: actions,
                                   deferImmediateClick: true).triggered.isEmpty)
        XCTAssertEqual(r.buttonUp(4, at: 1.10).triggered.map(\.action), [click])
    }
}
