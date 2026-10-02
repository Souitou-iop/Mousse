import XCTest
@testable import Mousse

final class ScrollSessionBoundaryTests: XCTestCase {
    func testDeviceAndEffectiveSettingsBoundaries() {
        var context: EventTapEngine.ScrollSessionContext?
        var settings = ScrollDeviceSettings()
        XCTAssertFalse(EventTapEngine.updateScrollContext(&context, deviceKey: "a", settings: settings))
        XCTAssertFalse(EventTapEngine.updateScrollContext(&context, deviceKey: "a", settings: settings))
        // Smooth -> Smooth, including equal settings, resets device-specific acceleration history.
        XCTAssertTrue(EventTapEngine.updateScrollContext(&context, deviceKey: "b", settings: settings))
        settings.scrollMode = .standard
        XCTAssertTrue(EventTapEngine.updateScrollContext(&context, deviceKey: "c", settings: settings))
        settings.reverseScroll = true
        XCTAssertTrue(EventTapEngine.updateScrollContext(&context, deviceKey: "c", settings: settings))
        XCTAssertFalse(EventTapEngine.updateScrollContext(&context, deviceKey: "c", settings: settings))
    }

    func testReloadOnlyInvalidatesChangedEffectiveBase() {
        var config = AppConfig()
        let global = EventTapEngine.ScrollSessionContext(deviceKey: "unknown", settings: config.scrollSettings)
        XCTAssertFalse(EventTapEngine.reloadInvalidatesScrollContext(global, config: config))
        config.showAutoScrollHUD.toggle()
        XCTAssertFalse(EventTapEngine.reloadInvalidatesScrollContext(global, config: config))
        var device = config.scrollSettings
        device.scrollSpeed = 2
        config.deviceProfiles = [DeviceProfile(id: "a", name: "A", settings: device)]
        let matched = EventTapEngine.ScrollSessionContext(deviceKey: "a", settings: device)
        config.scrollMode = .native
        XCTAssertTrue(EventTapEngine.reloadInvalidatesScrollContext(global, config: config))
        XCTAssertFalse(EventTapEngine.reloadInvalidatesScrollContext(matched, config: config))
        config.deviceProfiles[0].settings.scrollMode = .native
        XCTAssertTrue(EventTapEngine.reloadInvalidatesScrollContext(matched, config: config))
        config.deviceProfiles = []
        XCTAssertTrue(EventTapEngine.reloadInvalidatesScrollContext(matched, config: config))
        XCTAssertFalse(EventTapEngine.reloadInvalidatesScrollContext(nil, config: config))
    }

    func testReloadCancellationWithoutAnotherWheelDropsFeedTimeActionAndResetsQuantizer() throws {
        var posted: [Bool] = []
        let magnifier = MagnifySynthesizer(emitKeystroke: { posted.append($0) })
        var config = AppConfig()
        let context = EventTapEngine.ScrollSessionContext(deviceKey: "a", settings: config.scrollSettings)
        let old = try XCTUnwrap(magnifier.quantizedZoomAction(magnification: 0.15, at: 1))
        config.scrollMode = .native
        XCTAssertTrue(EventTapEngine.reloadInvalidatesScrollContext(context, config: config))
        // No new feed: reload cancellation runs on a different thread, before old action is enqueued.
        let cancelled = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            magnifier.endWheelZoomNow()
            cancelled.signal()
        }
        XCTAssertEqual(cancelled.wait(timeout: .now() + 2), .success)
        old()
        XCTAssertTrue(posted.isEmpty)
        // Neither carry nor last-fire rate limiting survives cancellation.
        XCTAssertNil(magnifier.quantizedZoomAction(magnification: 0.04, at: 1.01))
        let fresh = try XCTUnwrap(magnifier.quantizedZoomAction(magnification: 0.04, at: 1.02))
        fresh()
        XCTAssertEqual(posted, [true])
    }

    func testEmitterCanCancelWithoutHoldingQuantizerLock() throws {
        var magnifier: MagnifySynthesizer!
        var posted = 0
        magnifier = MagnifySynthesizer(emitKeystroke: { _ in
            posted += 1
            magnifier.endWheelZoomNow()
        })
        let admitted = try XCTUnwrap(magnifier.quantizedZoomAction(magnification: 0.075, at: 1))
        let queued = try XCTUnwrap(magnifier.quantizedZoomAction(magnification: 0.075, at: 1.2))
        admitted()
        queued()
        XCTAssertEqual(posted, 1)
    }
}
