import AppKit
import CoreGraphics
import QuartzCore
import SwiftUI

struct AutoScrollHUDPresentation: Equatable, Sendable {
    static let minimumArrowOpacity = 0.68
    static let minimumArrowLength = 9.0
    static let maximumArrowLength = 17.0

    let direction: CGVector
    let strength: Double

    static func make(velocity: CGVector, maxSpeed: Double = AutoScrollController.maxSpeed)
        -> AutoScrollHUDPresentation {
        let magnitude = hypot(velocity.dx, velocity.dy)
        guard magnitude > 0, maxSpeed > 0 else { return .neutral }
        return AutoScrollHUDPresentation(
            direction: CGVector(dx: velocity.dx / magnitude, dy: velocity.dy / magnitude),
            strength: min(magnitude / maxSpeed, 1))
    }

    static let neutral = AutoScrollHUDPresentation(direction: .zero, strength: 0)

    static func make(pointer: CGPoint, anchor: CGPoint, speed: Double, baseSpeed: Double,
                     deadzone: Double = AutoScrollController.deadzone,
                     maxSpeed: Double = AutoScrollController.maxSpeed)
        -> AutoScrollHUDPresentation {
        let offset = CGVector(dx: pointer.x - anchor.x, dy: anchor.y - pointer.y)
        let distance = hypot(offset.dx, offset.dy)
        guard abs(offset.dx) > deadzone || abs(offset.dy) > deadzone,
              distance > 0, maxSpeed > 0 else { return .neutral }
        let visualSpeed = min(max(baseSpeed + distance * speed, 0), maxSpeed)
        return AutoScrollHUDPresentation(
            direction: CGVector(dx: offset.dx / distance, dy: offset.dy / distance),
            strength: visualSpeed / maxSpeed)
    }

    var arrowOpacity: Double {
        Self.minimumArrowOpacity + (1 - Self.minimumArrowOpacity) * strength
    }

    var arrowLength: Double {
        Self.minimumArrowLength
            + (Self.maximumArrowLength - Self.minimumArrowLength) * strength
    }

    static func appKitPoint(forQuartzPoint point: CGPoint,
                            quartzBounds: CGRect,
                            appKitFrame: CGRect) -> CGPoint {
        CGPoint(
            x: appKitFrame.minX + point.x - quartzBounds.minX,
            y: appKitFrame.maxY - (point.y - quartzBounds.minY))
    }
}

struct AutoScrollHUDSmoother {
    private(set) var angle: Double?
    private(set) var strength = 0.0

    mutating func reset() {
        angle = nil
        strength = 0
    }

    mutating func advance(to target: AutoScrollHUDPresentation, deltaTime: Double,
                          response: Double = 30) -> AutoScrollHUDPresentation {
        guard target.strength > 0 else {
            reset()
            return .neutral
        }
        let targetAngle = atan2(target.direction.dy, target.direction.dx)
        guard let currentAngle = angle else {
            angle = targetAngle
            strength = target.strength
            return target
        }
        let dt = min(max(deltaTime, 0), 0.05)
        let alpha = 1 - exp(-response * dt)
        let delta = atan2(sin(targetAngle - currentAngle), cos(targetAngle - currentAngle))
        let nextAngle = currentAngle + delta * alpha
        angle = nextAngle
        strength += (target.strength - strength) * alpha
        return AutoScrollHUDPresentation(
            direction: CGVector(dx: cos(nextAngle), dy: sin(nextAngle)),
            strength: strength)
    }
}

struct AutoScrollHUDUpdate: Equatable {
    let anchor: CGPoint
    let speed: Double
    let baseSpeed: Double
    let generation: UInt64
}

struct AutoScrollHUDUpdateCoalescer {
    private(set) var pending: AutoScrollHUDUpdate?
    private(set) var lastDelivered: AutoScrollHUDUpdate?
    private(set) var isDeliveryScheduled = false

    mutating func submit(_ update: AutoScrollHUDUpdate) -> Bool {
        guard update != pending, update != lastDelivered else { return false }
        pending = update
        guard !isDeliveryScheduled else { return false }
        isDeliveryScheduled = true
        return true
    }

    mutating func takeLatest() -> AutoScrollHUDUpdate? {
        let update = pending
        pending = nil
        isDeliveryScheduled = false
        if let update { lastDelivered = update }
        return update
    }
}

struct AutoScrollHUDGenerationGate {
    private(set) var latestGeneration: UInt64 = 0

    mutating func accept(_ generation: UInt64) -> Bool {
        guard generation >= latestGeneration else { return false }
        latestGeneration = generation
        return true
    }

    func isCurrent(_ generation: UInt64) -> Bool {
        generation == latestGeneration
    }
}

enum AutoScrollExitDecision: Equatable {
    case none
    case cancelAndConsume
    case cancelAndPassThrough
    case cancelAndContinue
}

enum AutoScrollExitPolicy {
    static func decision(isActive: Bool, type: CGEventType, keyCode: UInt16? = nil,
                         scrollPhase: Int64 = 0, momentumPhase: Int64 = 0,
                         isSynthetic: Bool = false) -> AutoScrollExitDecision {
        guard isActive, !isSynthetic else { return .none }
        if type == .keyDown, keyCode == 53 { return .cancelAndConsume }
        if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
            return .cancelAndPassThrough
        }
        if type == .scrollWheel, scrollPhase == 0, momentumPhase == 0 {
            return .cancelAndContinue
        }
        return .none
    }
}

struct AutoScrollExitPassThroughTracker {
    private var buttons: Set<Int> = []

    mutating func begin(button: Int) {
        buttons.insert(button)
    }

    mutating func shouldPass(type: CGEventType, button: Int) -> Bool {
        guard buttons.contains(button), type == .otherMouseUp || type == .otherMouseDragged else {
            return false
        }
        if type == .otherMouseUp { buttons.remove(button) }
        return true
    }

    mutating func reset() {
        buttons.removeAll()
    }
}

final class AutoScrollHUDController: NSObject {
    static let shared = AutoScrollHUDController()

    private let model = AutoScrollHUDModel()
    private var panel: AutoScrollHUDPanel?
    private var generationGate = AutoScrollHUDGenerationGate()
    private let updateLock = NSLock()
    private var updateCoalescer = AutoScrollHUDUpdateCoalescer()
    private var currentUpdate: AutoScrollHUDUpdate?
    private var displayLink: CADisplayLink?
    private var displayID: CGDirectDisplayID = 0
    private var lastFrameTime = 0.0
    private var smoother = AutoScrollHUDSmoother()

    private static let panelSize = NSSize(width: 36, height: 36)
    private static let fadeInDuration = 0.10
    private static let fadeOutDuration = 0.08

    private override init() {
        super.init()
    }

    func enqueueUpdate(anchor: CGPoint, speed: Double, baseSpeed: Double, generation: UInt64) {
        let update = AutoScrollHUDUpdate(
            anchor: anchor, speed: speed, baseSpeed: baseSpeed, generation: generation)
        updateLock.lock()
        let shouldSchedule = updateCoalescer.submit(update)
        updateLock.unlock()
        guard shouldSchedule else { return }
        DispatchQueue.main.async { [weak self] in self?.deliverLatestUpdate() }
    }

    private func deliverLatestUpdate() {
        dispatchPrecondition(condition: .onQueue(.main))
        updateLock.lock()
        let update = updateCoalescer.takeLatest()
        updateLock.unlock()
        guard let update, generationGate.accept(update.generation) else { return }
        currentUpdate = update

        let panel = panel ?? makePanel()
        self.panel = panel
        guard let (point, screen, newDisplayID) = appKitPointAndScreen(for: update.anchor) else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: point.x - size.width / 2,
                                     y: point.y - size.height / 2))
        ensureDisplayLink(for: screen, displayID: newDisplayID)
        show(panel)
    }

    func hide(generation: UInt64) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard generationGate.accept(generation), let panel, panel.isVisible else { return }
        currentUpdate = nil
        displayLink?.isPaused = true
        lastFrameTime = 0
        smoother.reset()
        model.presentation = .neutral
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.alphaValue = 0
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeOutDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, weak panel] in
            guard let self, let panel, self.generationGate.isCurrent(generation) else { return }
            panel.orderOut(nil)
        }
    }

    private func makePanel() -> AutoScrollHUDPanel {
        let panel = AutoScrollHUDPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: AutoScrollHUDView(model: model))
        return panel
    }

    private func show(_ panel: AutoScrollHUDPanel) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !panel.isVisible {
            panel.alphaValue = reduceMotion ? 1 : 0
            panel.orderFrontRegardless()
        }
        guard !reduceMotion, panel.alphaValue < 1 else {
            panel.alphaValue = 1
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeInDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func ensureDisplayLink(for screen: NSScreen, displayID newDisplayID: CGDirectDisplayID) {
        if displayLink == nil || displayID != newDisplayID {
            displayLink?.invalidate()
            let link = screen.displayLink(target: self, selector: #selector(step(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
            displayID = newDisplayID
        }
        lastFrameTime = 0
        displayLink?.isPaused = false
    }

    @objc private func step(_ link: CADisplayLink) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let update = currentUpdate, let pointer = CGEvent(source: nil)?.location else { return }
        let target = AutoScrollHUDPresentation.make(
            pointer: pointer, anchor: update.anchor,
            speed: update.speed, baseSpeed: update.baseSpeed)
        let frameInterval = max(link.targetTimestamp - link.timestamp, 1.0 / 240.0)
        let dt = lastFrameTime > 0 ? link.targetTimestamp - lastFrameTime : frameInterval
        lastFrameTime = link.targetTimestamp
        model.presentation = smoother.advance(to: target, deltaTime: dt)
    }

    private func appKitPointAndScreen(for point: CGPoint)
        -> (point: CGPoint, screen: NSScreen, displayID: CGDirectDisplayID)? {
        var displayID: CGDirectDisplayID = 0
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(point, 1, &displayID, &count) == .success, count > 0,
              let screen = NSScreen.screens.first(where: {
                  ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
                      .uint32Value == displayID
              }) else { return nil }
        let converted = AutoScrollHUDPresentation.appKitPoint(
            forQuartzPoint: point,
            quartzBounds: CGDisplayBounds(displayID),
            appKitFrame: screen.frame)
        return (converted, screen, displayID)
    }
}

private final class AutoScrollHUDModel: ObservableObject {
    @Published var presentation = AutoScrollHUDPresentation.neutral
}

private final class AutoScrollHUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct AutoScrollHUDView: View {
    @ObservedObject var model: AutoScrollHUDModel

    var body: some View {
        AutoScrollHUDGlyph(presentation: model.presentation)
    }
}

struct AutoScrollHUDGlyph: View {
    let presentation: AutoScrollHUDPresentation

    var body: some View {
        ZStack {
            if presentation.strength > 0 {
                arrowPath
                    .stroke(.white.opacity(0.96),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .opacity(presentation.arrowOpacity)
                arrowPath
                    .stroke(.black.opacity(0.86),
                            style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    .opacity(presentation.arrowOpacity)
            }
            Circle()
                .fill(.white.opacity(0.96))
                .frame(width: 6.5, height: 6.5)
            Circle()
                .fill(.black.opacity(0.86))
                .frame(width: 4.5, height: 4.5)
        }
        .frame(width: 36, height: 36)
        .transaction { $0.animation = nil }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var arrowPath: Path {
        let center = CGPoint(x: 18, y: 18)
        let dx = presentation.direction.dx
        let dy = -presentation.direction.dy
        let start = CGPoint(x: center.x + dx * 3, y: center.y + dy * 3)
        let end = CGPoint(
            x: center.x + dx * presentation.arrowLength,
            y: center.y + dy * presentation.arrowLength)
        let angle = atan2(dy, dx)
        let wingLength = 5.0
        let wingAngle = Double.pi / 5
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        path.move(to: end)
        path.addLine(to: CGPoint(
            x: end.x - cos(angle - wingAngle) * wingLength,
            y: end.y - sin(angle - wingAngle) * wingLength))
        path.move(to: end)
        path.addLine(to: CGPoint(
            x: end.x - cos(angle + wingAngle) * wingLength,
            y: end.y - sin(angle + wingAngle) * wingLength))
        return path
    }
}
