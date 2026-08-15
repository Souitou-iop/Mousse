import AppKit
import CoreGraphics
import SwiftUI
import XCTest
@testable import Mousse

final class DiagnosticsTests: XCTestCase {
    @MainActor
    func testSettingsWindowConfigurationIsImmediateAndIdempotent() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 480),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false)

        SettingsWindowConfiguration.apply(to: window)
        SettingsWindowConfiguration.apply(to: window)

        XCTAssertEqual(window.identifier, SettingsWindowConfiguration.identifier)
        XCTAssertTrue(window.styleMask.contains(.miniaturizable))
        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertEqual(window.standardWindowButton(.miniaturizeButton)?.isHidden, false)
        XCTAssertEqual(window.standardWindowButton(.miniaturizeButton)?.isEnabled, true)
    }

    func testAutoScrollClickPolicyOnlyDelaysAutoScrollClicks() {
        XCTAssertEqual(
            EventTapEngine.buttonClickPolicy(
                actions: .init(click: .autoScroll), isDragButton: false,
                autoScrollClickDelay: 0.20),
            .confirmed(delay: 0.20))
        XCTAssertEqual(
            EventTapEngine.buttonClickPolicy(
                actions: .init(click: .navigateBack), isDragButton: true,
                autoScrollClickDelay: 0.20),
            .deferredUntilRelease)
        XCTAssertEqual(
            EventTapEngine.buttonClickPolicy(
                actions: .init(click: .navigateBack), isDragButton: false,
                autoScrollClickDelay: 0.20),
            .automatic)
    }

    func testHUDPresentationNormalizesDirectionAndCapsStrength() {
        let presentation = AutoScrollHUDPresentation.make(
            velocity: CGVector(dx: 3000, dy: 4000))

        XCTAssertEqual(presentation.direction.dx, 0.6, accuracy: 1e-9)
        XCTAssertEqual(presentation.direction.dy, 0.8, accuracy: 1e-9)
        XCTAssertEqual(presentation.strength, 1.0, accuracy: 1e-9)
    }

    func testHUDPresentationIsNeutralAtRest() {
        let presentation = AutoScrollHUDPresentation.make(velocity: .zero)

        XCTAssertEqual(presentation, .neutral)
        XCTAssertEqual(presentation.arrowOpacity, 0.68, accuracy: 1e-9)
        XCTAssertEqual(presentation.arrowLength, 9, accuracy: 1e-9)
    }

    func testHUDPresentationRotatesThroughCardinalDirections() {
        XCTAssertEqual(
            AutoScrollHUDPresentation.make(velocity: CGVector(dx: 4000, dy: 0)).direction,
            CGVector(dx: 1, dy: 0))
        XCTAssertEqual(
            AutoScrollHUDPresentation.make(velocity: CGVector(dx: -4000, dy: 0)).direction,
            CGVector(dx: -1, dy: 0))
        XCTAssertEqual(
            AutoScrollHUDPresentation.make(velocity: CGVector(dx: 0, dy: 4000)).direction,
            CGVector(dx: 0, dy: 1))
        XCTAssertEqual(
            AutoScrollHUDPresentation.make(velocity: CGVector(dx: 0, dy: -4000)).direction,
            CGVector(dx: 0, dy: -1))
    }

    func testHUDPresentationUsesStrengthForOpacityAndLength() {
        let presentation = AutoScrollHUDPresentation.make(velocity: CGVector(dx: 2000, dy: 0))

        XCTAssertEqual(presentation.strength, 0.5, accuracy: 1e-9)
        XCTAssertEqual(presentation.arrowOpacity, 0.84, accuracy: 1e-9)
        XCTAssertEqual(presentation.arrowLength, 13, accuracy: 1e-9)
    }

    func testHUDPointerDirectionPreservesScrollDeadzoneWithoutAxisSnapping() {
        let diagonal = AutoScrollHUDPresentation.make(
            pointer: CGPoint(x: 107, y: 94), anchor: CGPoint(x: 100, y: 100),
            speed: 100, baseSpeed: 0).direction
        XCTAssertEqual(diagonal.dx, 7 / sqrt(85), accuracy: 1e-12)
        XCTAssertEqual(diagonal.dy, 6 / sqrt(85), accuracy: 1e-12)
        XCTAssertEqual(
            AutoScrollHUDPresentation.make(
                pointer: CGPoint(x: 106, y: 94), anchor: CGPoint(x: 100, y: 100),
                speed: 100, baseSpeed: 0),
            .neutral)
    }

    func testHUDSmootherTakesShortestPathAcrossAngleWrap() {
        var smoother = AutoScrollHUDSmoother()
        let nearPi = Double.pi * 179 / 180
        _ = smoother.advance(
            to: AutoScrollHUDPresentation(
                direction: CGVector(dx: cos(nearPi), dy: sin(nearPi)),
                strength: 1),
            deltaTime: 1 / 60)
        let next = smoother.advance(
            to: AutoScrollHUDPresentation(
                direction: CGVector(dx: cos(-nearPi), dy: sin(-nearPi)),
                strength: 1),
            deltaTime: 1 / 60)

        XCTAssertLessThan(next.direction.dx, -0.99)
    }

    func testHUDSmoothingIsApproximatelyRefreshRateIndependent() {
        let start = AutoScrollHUDPresentation(direction: CGVector(dx: 1, dy: 0), strength: 0.2)
        let target = AutoScrollHUDPresentation(direction: CGVector(dx: 0, dy: 1), strength: 1)
        var at60Hz = AutoScrollHUDSmoother()
        var at120Hz = AutoScrollHUDSmoother()
        _ = at60Hz.advance(to: start, deltaTime: 1 / 60)
        _ = at120Hz.advance(to: start, deltaTime: 1 / 120)
        var result60 = start
        var result120 = start
        for _ in 0..<6 { result60 = at60Hz.advance(to: target, deltaTime: 1 / 60) }
        for _ in 0..<12 { result120 = at120Hz.advance(to: target, deltaTime: 1 / 120) }

        XCTAssertEqual(result60.direction.dx, result120.direction.dx, accuracy: 1e-9)
        XCTAssertEqual(result60.direction.dy, result120.direction.dy, accuracy: 1e-9)
        XCTAssertEqual(result60.strength, result120.strength, accuracy: 1e-9)
    }

    func testHUDUpdateCoalescerKeepsOnlyLatestUpdate() {
        var coalescer = AutoScrollHUDUpdateCoalescer()
        let first = AutoScrollHUDUpdate(
            anchor: CGPoint(x: 1, y: 1), speed: 10, baseSpeed: 20, generation: 1)
        let latest = AutoScrollHUDUpdate(
            anchor: CGPoint(x: 2, y: 2), speed: 30, baseSpeed: 40, generation: 1)

        XCTAssertTrue(coalescer.submit(first))
        XCTAssertFalse(coalescer.submit(latest))
        XCTAssertEqual(coalescer.takeLatest(), latest)
        XCTAssertFalse(coalescer.submit(latest))
    }

    func testHUDGenerationRejectsStaleUpdatesAndHideCompletions() {
        var gate = AutoScrollHUDGenerationGate()

        XCTAssertTrue(gate.accept(1))
        XCTAssertTrue(gate.accept(2))
        XCTAssertFalse(gate.accept(1))
        XCTAssertTrue(gate.accept(3))
        XCTAssertFalse(gate.isCurrent(2))
        XCTAssertTrue(gate.isCurrent(3))
    }

    @MainActor
    func testHUDGlyphRendersAcrossLightDarkAndColorBackgrounds() throws {
        let content = HStack(spacing: 0) {
            hudSnapshotTile(background: .white, velocity: .zero)
            hudSnapshotTile(background: .black, velocity: CGVector(dx: 0, dy: 4000))
            hudSnapshotTile(
                background: Color(red: 0.18, green: 0.42, blue: 0.72),
                velocity: CGVector(dx: 2600, dy: -3200))
            hudSnapshotTile(
                background: Color(red: 0.96, green: 0.96, blue: 0.93),
                velocity: CGVector(dx: -2000, dy: 0))
        }
        .frame(width: 320, height: 80)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        XCTAssertEqual(image.size, NSSize(width: 320, height: 80))

        let glyphRenderer = ImageRenderer(content:
            AutoScrollHUDGlyph(presentation: .make(velocity: CGVector(dx: 2000, dy: -2000))))
        glyphRenderer.scale = 2
        let glyphImage = try XCTUnwrap(glyphRenderer.nsImage)
        let glyphBitmap = try XCTUnwrap(
            glyphImage.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        XCTAssertEqual(glyphBitmap.colorAt(x: 0, y: 0)?.alphaComponent, 0)
        XCTAssertEqual(
            glyphBitmap.colorAt(x: glyphBitmap.pixelsWide - 1,
                                y: glyphBitmap.pixelsHigh - 1)?.alphaComponent,
            0)

        if let directory = ProcessInfo.processInfo.environment["MOUSSE_HUD_SNAPSHOT_DIR"] {
            let url = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent("auto-scroll-hud.png")
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
        }
    }

    private func hudSnapshotTile(background: Color, velocity: CGVector) -> some View {
        ZStack {
            background
            AutoScrollHUDGlyph(presentation: .make(velocity: velocity))
        }
        .frame(width: 80, height: 80)
    }

    func testHUDConvertsQuartzPointToAppKitCoordinates() {
        let point = AutoScrollHUDPresentation.appKitPoint(
            forQuartzPoint: CGPoint(x: 120, y: 80),
            quartzBounds: CGRect(x: 0, y: 0, width: 1440, height: 900),
            appKitFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))

        XCTAssertEqual(point, CGPoint(x: 120, y: 820))
    }

    func testAutoScrollExitPolicyMatchesRequestedInputs() {
        XCTAssertEqual(
            AutoScrollExitPolicy.decision(isActive: true, type: .keyDown, keyCode: 53),
            .cancelAndConsume)
        XCTAssertEqual(
            AutoScrollExitPolicy.decision(isActive: true, type: .leftMouseDown),
            .cancelAndPassThrough)
        XCTAssertEqual(
            AutoScrollExitPolicy.decision(isActive: true, type: .otherMouseDown),
            .cancelAndPassThrough)
        XCTAssertEqual(
            AutoScrollExitPolicy.decision(isActive: true, type: .scrollWheel),
            .cancelAndContinue)
        XCTAssertEqual(
            AutoScrollExitPolicy.decision(isActive: true, type: .scrollWheel, scrollPhase: 1),
            .none)
        XCTAssertEqual(
            AutoScrollExitPolicy.decision(isActive: true, type: .scrollWheel, isSynthetic: true),
            .none)
    }

    func testSideButtonExitPassesDragAndMatchingRelease() {
        var tracker = AutoScrollExitPassThroughTracker()
        tracker.begin(button: 4)

        XCTAssertTrue(tracker.shouldPass(type: .otherMouseDragged, button: 4))
        XCTAssertFalse(tracker.shouldPass(type: .otherMouseUp, button: 5))
        XCTAssertTrue(tracker.shouldPass(type: .otherMouseUp, button: 4))
        XCTAssertFalse(tracker.shouldPass(type: .otherMouseUp, button: 4))
    }

    func testEventTapHealthTransitions() {
        let now = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(EventTapHealth.resolve(hasTap: false, tapEnabled: false,
                                               lastRecoveryAt: nil, now: now), .initializing)
        XCTAssertEqual(EventTapHealth.resolve(hasTap: true, tapEnabled: true,
                                               lastRecoveryAt: nil, now: now), .healthy)
        XCTAssertEqual(EventTapHealth.resolve(hasTap: true, tapEnabled: false,
                                               lastRecoveryAt: nil, now: now), .recovering)
        XCTAssertEqual(EventTapHealth.resolve(
            hasTap: true, tapEnabled: true,
            lastRecoveryAt: Date(timeIntervalSince1970: 99), now: now), .recovering)
        XCTAssertEqual(EventTapHealth.resolve(
            hasTap: true, tapEnabled: true,
            lastRecoveryAt: Date(timeIntervalSince1970: 97), now: now), .healthy)
    }

    func testDetectedMiceDeduplicateAndSort() {
        let mice = DetectedMouse.deduplicated([
            DetectedMouse(id: "b", name: "Zeta"),
            DetectedMouse(id: "a", name: "Alpha"),
            DetectedMouse(id: "a", name: "Alpha (duplicate)"),
        ])

        XCTAssertEqual(mice.map(\.id), ["a", "b"])
        XCTAssertEqual(mice.map(\.name), ["Alpha (duplicate)", "Zeta"])
    }

    func testLastTriggeredActionRecordsLatestButtonAndTime() {
        let date = Date(timeIntervalSince1970: 123)
        let output = ButtonTriggerRecognizer.Output(triggered: [
            .init(button: 4, action: .navigateBack),
            .init(button: 5, action: .navigateForward),
        ])

        let last = LastTriggeredAction.latest(in: output, at: date)
        XCTAssertEqual(last?.button, 5)
        XCTAssertEqual(last?.action, .navigateForward)
        XCTAssertEqual(last?.triggeredAt, date)
    }
}
