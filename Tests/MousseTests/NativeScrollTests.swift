import XCTest
import CoreGraphics
@testable import Mousse

final class NativeScrollTests: XCTestCase {
    func testNativeAndDeviceRoundTripWithoutMigratingLegacyStandard() throws {
        var config = AppConfig()
        config.scrollMode = .native
        var settings = config.scrollSettings
        settings.scrollSpeed = 3
        settings.zoomSpeed = 6
        config.deviceProfiles = [DeviceProfile(id: "046d:c548", name: "Mouse", settings: settings)]
        let decoded = try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(decoded, config)
        XCTAssertEqual(decoded.deviceProfiles[0].settings.scrollMode, .native)
        XCTAssertEqual(EventTapEngine.resolveDeviceScrollSettings(activeKey: "046d:c548",
            profiles: ["046d:c548": settings], global: ScrollDeviceSettings()).scrollMode, .native)
        for json in [#"{"scrollMode":"standard"}"#, #"{"smoothScroll":false}"#] {
            XCTAssertEqual(try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8)).scrollMode, .standard)
        }
    }

    func testMenuSmoothToggleDoesNotTreatNativeAsSmooth() {
        XCTAssertFalse(ScrollMode.native.isSmooth)
        XCTAssertFalse(ScrollMode.standard.isSmooth)
        XCTAssertTrue(ScrollMode.smooth.isSmooth)
        XCTAssertTrue(ScrollMode.smoothStep.isSmooth)
        XCTAssertEqual(ScrollMode.fromSmoothToggle(false), .standard)
        XCTAssertEqual(ScrollMode.fromSmoothToggle(true), .smooth)
    }

    func testNativeIgnoresOrdinaryAppDirectionAndExclusionRules() {
        let profile = ScrollAppProfile(bundleID: "app", mousseScrollEnabled: true,
                                       reverseScroll: true, reverseScrollHorizontal: false)
        let native = EventTapEngine.resolveScrollAppSettings(bundleID: "app", profiles: ["app": profile],
            excluded: ["app"], globalReverse: false, globalReverseHorizontal: true, mode: .native)
        XCTAssertEqual(native, .init(mousseScrollEnabled: false, reverseScroll: false, reverseScrollHorizontal: true))
        let standard = EventTapEngine.resolveScrollAppSettings(bundleID: "app", profiles: ["app": profile],
            excluded: ["app"], globalReverse: false, globalReverseHorizontal: true, mode: .standard)
        XCTAssertEqual(standard, .init(mousseScrollEnabled: true, reverseScroll: true, reverseScrollHorizontal: false))
        XCTAssertEqual(EventTapEngine.resolveScrollAppSettings(bundleID: nil, profiles: [:], excluded: [],
            globalReverse: true, globalReverseHorizontal: false, mode: .native),
            .init(mousseScrollEnabled: false, reverseScroll: true, reverseScrollHorizontal: false))
    }

    func testNativeOriginalEventKeepsAllModifiersAndMetadataWithoutTransposeOrZoom() throws {
        for units in [CGScrollEventUnit.line, .pixel] {
            let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: units,
                wheelCount: 2, wheel1: 3, wheel2: -2, wheel3: 0))
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 1.25)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -2.5)
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 37)
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: -19)
            event.setIntegerValueField(.eventSourceUserData, value: 12345)
            event.setIntegerValueField(.eventSourceUnixProcessID, value: 321)
            event.flags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
            let flags = event.flags
            let timestamp = event.timestamp
            let lineV = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            let lineH = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
            let originalContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous)
            let out = EventTapEngine.applyNativeWheel(event, settings: .init(mousseScrollEnabled: false,
                                                                           reverseScroll: true))
            XCTAssertTrue(out === event)
            XCTAssertEqual(out.flags, flags)
            XCTAssertEqual(out.timestamp, timestamp)
            XCTAssertEqual(out.getIntegerValueField(.eventSourceUserData), 12345)
            XCTAssertEqual(out.getIntegerValueField(.eventSourceUnixProcessID), 321)
            XCTAssertEqual(out.getIntegerValueField(.scrollWheelEventIsContinuous), originalContinuous)
            XCTAssertEqual(out.getIntegerValueField(.scrollWheelEventDeltaAxis1), -lineV)
            XCTAssertEqual(out.getIntegerValueField(.scrollWheelEventDeltaAxis2), lineH)
            XCTAssertEqual(out.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1), -1.25)
            XCTAssertEqual(out.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2), -2.5)
            XCTAssertEqual(out.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), -37)
            XCTAssertEqual(out.getIntegerValueField(.scrollWheelEventPointDeltaAxis2), -19)
        }
    }

    func testNativeTrackpadAndSafetyBypassesStayOriginal() throws {
        let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
            wheelCount: 2, wheel1: 30, wheel2: 0, wheel3: 0))
        for field in [CGEventField(rawValue: 99)!, CGEventField(rawValue: 123)!] {
            event.setIntegerValueField(field, value: 1)
            XCTAssertFalse(EventTapEngine.isPhysicalWheel(event))
            let out = EventTapEngine.applyNativeWheel(event, settings: .init(mousseScrollEnabled: false, reverseScroll: true))
            XCTAssertTrue(out === event)
            XCTAssertEqual(out.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), 30)
            event.setIntegerValueField(field, value: 0)
        }
        for terminal in ["com.apple.Terminal", "com.googlecode.iterm2"] {
            let settings = EventTapEngine.resolveScrollAppSettings(bundleID: terminal, profiles: [:], excluded: [],
                globalReverse: true, globalReverseHorizontal: true, mode: .native)
            XCTAssertEqual(settings, .init(mousseScrollEnabled: false, reverseScroll: false))
        }
        let mirror = EventTapEngine.resolveScrollAppSettings(bundleID: "com.apple.ScreenContinuity",
            profiles: [:], excluded: [], globalReverse: true, globalReverseHorizontal: false, mode: .native)
        XCTAssertFalse(mirror.mousseScrollEnabled)
        XCTAssertTrue(EventTapEngine.applyNativeWheel(event, settings: mirror) === event)
        XCTAssertTrue(EventTapEngine.isScrollSafetyBypassed(bundleID: "remote", remoteDesktopBypass: true,
            remoteDesktopBundles: ["remote"], gameBypass: false, gameBundles: []))
        XCTAssertTrue(EventTapEngine.isScrollSafetyBypassed(bundleID: "game", remoteDesktopBypass: false,
            remoteDesktopBundles: [], gameBypass: true, gameBundles: ["game"]))
        XCTAssertFalse(EventTapEngine.isScrollSafetyBypassed(bundleID: "game", remoteDesktopBypass: false,
            remoteDesktopBundles: [], gameBypass: false, gameBundles: ["game"]))
    }

    func testEnteringNativeCancelsQueuedFallbackZoomWithoutPostingKeys() {
        var posted: [Bool] = []
        let magnifier = MagnifySynthesizer(emitKeystroke: { posted.append($0) })
        let oldAction = magnifier.fallbackZoomAction(zoomIn: true)
        magnifier.endWheelZoomNow()
        oldAction()
        XCTAssertTrue(posted.isEmpty)
        magnifier.fallbackZoomAction(zoomIn: false)()
        XCTAssertEqual(posted, [false])
    }
    func testFallbackEmitterRunsOutsideCancellationLock() {
        var magnifier: MagnifySynthesizer!
        var emitted = 0
        magnifier = MagnifySynthesizer(emitKeystroke: { _ in
            emitted += 1
            magnifier.endWheelZoomNow()
        })
        let admitted = magnifier.fallbackZoomAction(zoomIn: true)
        let queued = magnifier.fallbackZoomAction(zoomIn: false)
        admitted()
        queued()
        XCTAssertEqual(emitted, 1)
    }

}
