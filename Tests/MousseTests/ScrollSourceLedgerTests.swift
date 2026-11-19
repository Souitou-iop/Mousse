import XCTest
@testable import Mousse

/// Guards the injected-scroll safety bypass: the classification rule and the diagnostics ledger
/// that records which remote processes injected wheel events (UU 远控 etc.).
final class ScrollSourceLedgerTests: XCTestCase {

    // MARK: classification

    func testHardwareSignatureIsNeverInjected() {
        // HID system state + no posting process — every physical wheel event.
        XCTAssertFalse(EventTapEngine.isInjectedScrollEvent(
            sourceStateID: EventTapEngine.hardwareScrollSourceStateID, sourceProcessID: 0))
    }

    func testPartialDeviationsAreNotInjected() {
        // Both fields must deviate: a lone unexpected field (e.g. an OS-synthesized event with a
        // non-HID state but no posting process) must NOT disable reversal on physical input.
        let hardware = EventTapEngine.hardwareScrollSourceStateID
        XCTAssertFalse(EventTapEngine.isInjectedScrollEvent(
            sourceStateID: hardware, sourceProcessID: 4242))
        XCTAssertFalse(EventTapEngine.isInjectedScrollEvent(
            sourceStateID: hardware + 1, sourceProcessID: 0))
    }

    func testRemoteControlSignatureIsInjected() {
        // CGEventPost over the combined session state: state 0 + the posting PID.
        XCTAssertTrue(EventTapEngine.isInjectedScrollEvent(sourceStateID: 0, sourceProcessID: 4242))
        // A private CGEventSource gets its own state ID.
        XCTAssertTrue(EventTapEngine.isInjectedScrollEvent(sourceStateID: -7, sourceProcessID: 4242))
    }

    // MARK: ledger

    func testLedgerAggregatesBySourceAndCountsTotal() {
        var ledger = ScrollSourceLedger()
        let t0 = Date(timeIntervalSince1970: 100)
        ledger.record(sourceStateID: 0, sourceProcessID: 4242, processName: "UURemoteServer", at: t0)
        ledger.record(sourceStateID: 0, sourceProcessID: 4242, processName: nil, at: t0.addingTimeInterval(1))
        ledger.record(sourceStateID: 0, sourceProcessID: 500, processName: "TeamViewer", at: t0.addingTimeInterval(2))

        XCTAssertEqual(ledger.totalCount, 3)
        XCTAssertEqual(ledger.samples.count, 2)
        let uu = ledger.samples.first { $0.sourceProcessID == 4242 }
        XCTAssertEqual(uu?.processName, "UURemoteServer")
        XCTAssertEqual(uu?.count, 2)
        XCTAssertEqual(uu?.lastAt, t0.addingTimeInterval(1))
        XCTAssertEqual(ledger.lastAt, t0.addingTimeInterval(2))
        // A nil name must not overwrite a resolved one.
        ledger.record(sourceStateID: 0, sourceProcessID: 4242, processName: nil, at: t0.addingTimeInterval(3))
        XCTAssertEqual(ledger.samples.first { $0.sourceProcessID == 4242 }?.processName, "UURemoteServer")
    }

    func testLedgerCapsSamplesDroppingOldest() {
        var ledger = ScrollSourceLedger()
        let t0 = Date(timeIntervalSince1970: 0)
        for pid in 0..<(ScrollSourceLedger.sampleLimit + 2) {
            ledger.record(sourceStateID: 0, sourceProcessID: Int64(pid), processName: nil,
                          at: t0.addingTimeInterval(Double(pid)))
        }
        XCTAssertEqual(ledger.samples.count, ScrollSourceLedger.sampleLimit)
        XCTAssertEqual(ledger.totalCount, ScrollSourceLedger.sampleLimit + 2)
        // The two oldest PIDs were evicted; the newest survive.
        XCTAssertFalse(ledger.samples.contains { $0.sourceProcessID == 0 })
        XCTAssertEqual(ledger.samples.map(\.sourceProcessID).max(),
                       Int64(ScrollSourceLedger.sampleLimit + 1))
    }

    func testProcessNameResolvesLivePID() {
        // A live PID resolves to a bare executable name; the exact binary differs between the
        // test host and packaged app, so only assert the shape.
        let name = EventTapEngine.processName(forPID: Int64(ProcessInfo.processInfo.processIdentifier))
        XCTAssertNotNil(name)
        XCTAssertEqual(name?.contains("/"), false)
        XCTAssertNil(EventTapEngine.processName(forPID: -1))
    }
}
