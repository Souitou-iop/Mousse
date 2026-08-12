import XCTest
@testable import Mousse

final class ButtonCaptureRecognizerTests: XCTestCase {
    private func recognizer() -> ButtonCaptureRecognizer {
        let result = ButtonCaptureRecognizer()
        result.doubleClickInterval = 0.26
        result.holdDuration = 0.50
        result.start()
        return result
    }

    func testSingleClickWaitsForDoubleClickDeadline() {
        let r = recognizer()
        XCTAssertNil(r.buttonDown(4, at: 1))
        XCTAssertNil(r.buttonUp(4, at: 1.05))
        XCTAssertNil(r.advance(to: 1.25))
        XCTAssertEqual(r.advance(to: 1.26), .init(buttonNumber: 4, trigger: .click))
    }

    func testSecondPressRecognizesDoubleClick() {
        let r = recognizer()
        _ = r.buttonDown(4, at: 1)
        _ = r.buttonUp(4, at: 1.05)
        XCTAssertEqual(r.buttonDown(4, at: 1.20),
                       .init(buttonNumber: 4, trigger: .doubleClick))
    }

    func testLateSecondPressCompletesFirstClick() {
        let r = recognizer()
        _ = r.buttonDown(4, at: 1)
        _ = r.buttonUp(4, at: 1.05)
        XCTAssertEqual(r.buttonDown(4, at: 1.27),
                       .init(buttonNumber: 4, trigger: .click))
    }

    func testHoldRecognizesAtThreshold() {
        let r = recognizer()
        _ = r.buttonDown(5, at: 2)
        XCTAssertNil(r.advance(to: 2.49))
        XCTAssertEqual(r.advance(to: 2.50), .init(buttonNumber: 5, trigger: .hold))
    }

    func testOtherButtonsAreIgnoredDuringCandidate() {
        let r = recognizer()
        _ = r.buttonDown(4, at: 1)
        XCTAssertNil(r.buttonDown(5, at: 1.10))
        XCTAssertNil(r.buttonUp(5, at: 1.15))
        _ = r.buttonUp(4, at: 1.20)
        XCTAssertEqual(r.advance(to: 1.26), .init(buttonNumber: 4, trigger: .click))
    }

    func testOtherButtonsAreIgnoredWhileWaitingForDoubleClick() {
        let r = recognizer()
        _ = r.buttonDown(4, at: 1)
        _ = r.buttonUp(4, at: 1.05)
        XCTAssertNil(r.buttonDown(5, at: 1.10))
        XCTAssertNil(r.buttonUp(5, at: 1.15))
        XCTAssertEqual(r.buttonDown(4, at: 1.20),
                       .init(buttonNumber: 4, trigger: .doubleClick))
    }

    func testCancelClearsPendingCapture() {
        let r = recognizer()
        _ = r.buttonDown(4, at: 1)
        r.cancel()
        XCTAssertNil(r.advance(to: 2))
        XCTAssertNil(r.nextDeadline)
    }

    func testReleasedAfterDoubleClickDeadlineCompletesImmediately() {
        let r = recognizer()
        _ = r.buttonDown(4, at: 1)
        XCTAssertEqual(r.buttonUp(4, at: 1.27),
                       .init(buttonNumber: 4, trigger: .click))
    }

    func testMinimumHoldDuration() {
        let r = recognizer()
        r.holdDuration = 0.10
        _ = r.buttonDown(4, at: 1)
        XCTAssertNil(r.advance(to: 1.099))
        XCTAssertEqual(r.advance(to: 1.10), .init(buttonNumber: 4, trigger: .hold))
    }

    func testMaximumHoldDuration() {
        let r = recognizer()
        r.holdDuration = 0.80
        _ = r.buttonDown(4, at: 1)
        XCTAssertNil(r.advance(to: 1.799))
        XCTAssertEqual(r.advance(to: 1.80), .init(buttonNumber: 4, trigger: .hold))
    }
}
