import AppKit
import CoreGraphics
import Foundation
import IOKit.hid
import QuartzCore
import os

/// Owns the CGEventTap that intercepts mouse buttons and scroll, running on a dedicated
/// high-priority thread (never the main thread — a stalled main thread would time out the tap).
final class EventTapEngine {

    enum CaptureStartStatus: Equatable {
        case started
        case accessibilityRequired
        case eventTapInitializing
    }

    struct KeyboardCaptureResult: Equatable, Sendable {
        let keyCode: UInt16
        let control: Bool
        let option: Bool
        let command: Bool
        let shift: Bool

        var action: RemapAction {
            .keyStroke(keyCode: keyCode, control: control, option: option,
                       command: command, shift: shift)
        }
    }

    enum CaptureOutcome<Value> {
        case captured(Value)
        case cancelled
        case timedOut
    }

    private enum CaptureKind { case none, mouse, keyboard }

    static let shared = EventTapEngine()
    private init() {}

    /// Published by the tap thread once `tapCreate` succeeds, read by the main thread (watchdog,
    /// wake notifications) — so it lives under `lock` like the rest of the shared state.
    private var tap: CFMachPort?
    private var keyboardCaptureTap: CFMachPort?
    private var thread: Thread?
    private var watchdog: Timer?
    private var hidManager: IOHIDManager?

    // Snapshot read by the tap callback thread; guarded by `lock`.
    private let lock = OSAllocatedUnfairLock()
    private var enabled = true
    private var reverseScroll = false
    private var scrollMode: ScrollMode = .smooth
    private var scrollSmoothness: ScrollSmoothness = .balanced
    private var scrollSpeed = 0.5
    private var zoomSpeed = 1.0
    private var scrollLines = 3
    private var scrollAcceleration = true
    private var smoothHighRes = false
    private var doubleClickInterval = 0.26
    private var holdDuration = 0.50
    private var spaceDragButton = 0
    private var spaceDragThreshold = 200.0
    private var spaceDragReverse = false
    private var spaceDragFollowFinger = true
    private var spaceDragLockPointer = true
    private var holdScrollByButton: [Int: RemapAction.ScrollOutput] = [:]
    private var edgeScrollEnabled = false
    private var edgeScrollSpeed = 400.0
    // Tap-thread only (like the other gesture state): the detector and the timestamp of the last
    // REAL wheel input, which resets the edge-scroll rest timer (user input takes priority).
    private var edgeScrollDetector = EdgeScrollDetector()
    private var lastRealWheelAt = 0.0
    private var captureKind: CaptureKind = .none
    private var captureCompletion: ((CaptureOutcome<Int>) -> Void)?
    private var keyboardCaptureCompletion: ((CaptureOutcome<KeyboardCaptureResult>) -> Void)?
    private var suppressedCaptureButton: Int?
    /// Capture must never outlive the Settings interaction that opened it: while it is on, every
    /// mouse button passes through unmapped and the Space-drag gesture is bypassed, so a UI path
    /// that fails to close it (a capture click that lands in another app, a window torn down
    /// without `onDisappear`) would silently kill every remap until relaunch. Expiring it here
    /// means no UI bug can strand the engine.
    private var captureDeadline = 0.0
    private static let captureMaxDuration = 30.0
    private var excludedBundleIDs: Set<String> = []

    /// Terminal emulators are always excluded from smoothing (merged with the user's list).
    /// They are line-grid UIs that translate accumulated scroll PIXELS into mouse-reporting
    /// wheel events (vim/tmux then multiply each by ~3 lines) — an accelerated glide of
    /// 30–100 px per notch therefore jumps 10-30 text lines no matter what the legacy line
    /// fields say. Native notch events are the only stream terminals interpret at wheel scale.
    /// (Warp is deliberately NOT here — it renders pixel scrolling natively and stays smooth.)
    private static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "net.kovidgoyal.kitty",
        "com.github.wez.wezterm", "com.mitchellh.ghostty",
        "org.alacritty", "co.zeit.hyper", "app.tabby",
    ]
    private var verticalToHorizontalBundleIDs: Set<String> = []
    private static let chromiumBundlePrefixes = [
        "com.google.Chrome", "org.chromium.Chromium", "com.operasoftware.Opera",
        "com.microsoft.edgemac", "com.vivaldi.Vivaldi", "com.brave.Browser",
    ]
    private var mappingsByButton: [Int: ButtonTriggerRecognizer.Actions] = [:]
    private var pendingDragCancel = false // set on wake/device-change, consumed on the tap thread
    private var pendingTriggerCancel = false
    private var pendingCursorFlush = false

    /// Source for the fresh wheel events we post to reverse Standard-mode scrolling (see below).
    private let scrollSource = CGEventSource(stateID: .hidSystemState)

    /// Fractional line-delta carry for `postContinuous` (1 line ≈ 10 px). Without it, slow hi-res
    /// scrolls (< 10 px/event) would truncate to 0 lines on every event and terminals in
    /// mouse-reporting mode would never move. Only touched on the tap thread.
    private var contLineCarryV = 0.0
    private var contLineCarryH = 0.0

    /// Smooth scrolling + drag-to-switch-Spaces; only ever touched on the tap thread.
    private let scrollAnimator = ScrollAnimator()
    private let magnifier = MagnifySynthesizer()
    private let spaceDrag = SpaceDragGesture()
    private let holdScroll = HoldScrollGesture()
    private let autoScroll = AutoScrollController() // tap-thread only, like the other gestures
    private let buttonTriggers = ButtonTriggerRecognizer()
    private var buttonTriggerTimer: CFRunLoopTimer?
    private var eventTapRunLoop: CFRunLoop?
    private let cursorApp = CursorAppResolver() // tap-thread only, like the animator

    /// Start the tap thread (idempotent). Apply `config`.
    func start(config: AppConfig) {
        reload(config)
        // Wire the drag gesture's pointer-freeze hooks to the real implementation. Both the gesture
        // state and PointerFreeze are tap-thread-only, so these closures only ever run there.
        spaceDrag.freezePointer = { [weak self] in
            guard let self else { return }
            PointerFreeze.shared.freeze(at: self.spaceDrag.pointerLocation())
        }
        spaceDrag.unfreezePointer = { PointerFreeze.shared.unfreeze() }
        holdScroll.volumeStep = { steps in
            // Tap thread (handleScroll runs there) — MediaKey.post is already used from this
            // thread by the regular remap path.
            (steps > 0 ? MediaKey.volumeUp : MediaKey.volumeDown).post()
        }
        guard thread == nil else { return }
        let t = Thread { [weak self] in self?.threadMain() }
        t.name = "com.mousse.event-tap"
        t.qualityOfService = .userInteractive
        thread = t
        t.start()

        // macOS often disables the tap across sleep/wake WITHOUT delivering a
        // tapDisabledByTimeout event to our callback — so the callback's re-enable never fires
        // and the whole tap (scroll + Space-drag) stays dead until relaunch. Proactively re-enable
        // on wake, and keep a light watchdog as a safety net for silent disables.
        let wsCenter = NSWorkspace.shared.notificationCenter
        wsCenter.addObserver(self, selector: #selector(handleWake),
                             name: NSWorkspace.didWakeNotification, object: nil)
        wsCenter.addObserver(self, selector: #selector(handleWake),
                             name: NSWorkspace.screensDidWakeNotification, object: nil)
        // Plugging/unplugging an external display or changing resolution invalidates the scroll
        // animator's CADisplayLink the same way sleep does — rebuild it so scroll never silently dies.
        NotificationCenter.default.addObserver(self, selector: #selector(handleWake),
                             name: NSApplication.didChangeScreenParametersNotification, object: nil)
        // A smooth gesture that spans a Space switch (or app activation) gets orphaned and ignored by
        // the newly-focused window — close it immediately so the next scroll opens a fresh gesture.
        wsCenter.addObserver(self, selector: #selector(handleContextChange),
                             name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        wsCenter.addObserver(self, selector: #selector(handleContextChange),
                             name: NSWorkspace.didActivateApplicationNotification, object: nil)
        startWatchdog()
        startDeviceMonitor()
    }

    /// Space/app-focus changed — end any in-flight smooth gesture so it can't get orphaned across the
    /// boundary (harmless no-op when no gesture is active).
    @objc func handleContextChange() {
        scrollAnimator.endGestureNow()
        magnifier.endNow()
        lock.lock(); pendingCursorFlush = true; lock.unlock()
    }

    /// A mouse (dis)connected — e.g. changing the report rate re-enumerates it on USB, which orphans
    /// an in-flight smooth gesture just like a Space switch. Re-enable the tap and end the gesture so
    /// the next scroll starts fresh.
    private func handleDeviceChange() {
        reEnableTap()
        scrollAnimator.endGestureNow()
        requestInputCancel()
    }

    /// The Space-drag button's up can be lost across sleep or a device disconnect, leaving the
    /// gesture stuck `down` (it would then swallow every drag and fire spurious Space switches).
    /// The gesture's state is tap-thread-only, so don't touch it here — raise a flag the tap
    /// callback consumes at the top of its next event.
    private func requestInputCancel() {
        let mouseCancellation: ((CaptureOutcome<Int>) -> Void)?
        let keyboardCancellation: ((CaptureOutcome<KeyboardCaptureResult>) -> Void)?
        lock.lock()
        pendingDragCancel = true
        pendingTriggerCancel = true
        (mouseCancellation, keyboardCancellation) = cancelCaptureLocked()
        let keyboardTap = keyboardCaptureTap
        lock.unlock()
        if let keyboardTap { CGEvent.tapEnable(tap: keyboardTap, enable: false) }
        if let mouseCancellation { DispatchQueue.main.async { mouseCancellation(.cancelled) } }
        if let keyboardCancellation { DispatchQueue.main.async { keyboardCancellation(.cancelled) } }
        wakeTriggerTimer(at: CACurrentMediaTime())
    }

    /// Watch for mice connecting/disconnecting via IOKit. Device matching/removal notifications need no
    /// Input-Monitoring permission (we never read input values) — they just tell us when to recover.
    private func startDeviceMonitor() {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Mouse,
        ]
        IOHIDManagerSetDeviceMatching(mgr, match as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        let cb: IOHIDDeviceCallback = { context, _, _, _ in
            guard let context else { return }
            Unmanaged<EventTapEngine>.fromOpaque(context).takeUnretainedValue().handleDeviceChange()
        }
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, cb, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, cb, ctx)
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let opened = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        if opened != kIOReturnSuccess {
            // Non-fatal: device callbacks won't fire, so report-rate re-enumeration recovery is skipped
            // (Space/app-switch recovery is unaffected). Log so a silent failure is diagnosable.
            NSLog("Mousse: IOHIDManagerOpen failed (0x%X) — report-rate scroll recovery disabled", opened)
        }
        hidManager = mgr
    }

    /// On wake, re-enable the tap AND rebuild the scroll animator's display link, which macOS
    /// invalidates across sleep (leaving smooth scroll dead until it eventually self-heals).
    @objc func handleWake() {
        reEnableTap()
        scrollAnimator.handleWake()
        magnifier.endNow()
        requestInputCancel()
        lock.lock(); pendingCursorFlush = true; lock.unlock()
    }

    /// Re-enable the tap if macOS disabled it (e.g. across sleep/wake). Safe to call from any thread
    /// and idempotent — tapEnable on an already-enabled tap is a no-op.
    @objc func reEnableTap() {
        lock.lock(); let tap = self.tap; lock.unlock()
        guard let tap else { return }
        if !CGEvent.tapIsEnabled(tap: tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
            NSLog("Mousse: event tap was disabled (sleep/wake?), re-enabled")
        }
    }

    /// Periodically poll for a silently-disabled tap. 2s is invisible to the user yet costs nothing.
    private func startWatchdog() {
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in self?.reEnableTap() }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    /// Start learning a physical button. The event tap owns capture so the press, drag, and release
    /// can be swallowed globally instead of leaking into the app under the pointer.
    @discardableResult
    func beginCapture(
        completion: @escaping (CaptureOutcome<Int>) -> Void
    ) -> CaptureStartStatus {
        guard AccessibilityPermission.isTrusted else { return .accessibilityRequired }
        var oldMouseCompletion: ((CaptureOutcome<Int>) -> Void)?
        var oldKeyboardCompletion: ((CaptureOutcome<KeyboardCaptureResult>) -> Void)?
        lock.lock()
        guard let tap, CGEvent.tapIsEnabled(tap: tap) else {
            lock.unlock()
            return .eventTapInitializing
        }
        oldMouseCompletion = captureCompletion
        oldKeyboardCompletion = keyboardCaptureCompletion
        captureKind = .mouse
        captureCompletion = completion
        keyboardCaptureCompletion = nil
        pendingDragCancel = true
        pendingTriggerCancel = true
        captureDeadline = CACurrentMediaTime() + EventTapEngine.captureMaxDuration
        let deadline = captureDeadline
        let keyboardTap = keyboardCaptureTap
        lock.unlock()
        if let keyboardTap { CGEvent.tapEnable(tap: keyboardTap, enable: false) }
        if let oldMouseCompletion { DispatchQueue.main.async { oldMouseCompletion(.cancelled) } }
        if let oldKeyboardCompletion { DispatchQueue.main.async { oldKeyboardCompletion(.cancelled) } }
        NSLog("Mousse: mouse capture started")
        wakeTriggerTimer(at: deadline)
        return .started
    }

    func cancelCapture() {
        let mouseCompletion: ((CaptureOutcome<Int>) -> Void)?
        let keyboardCompletion: ((CaptureOutcome<KeyboardCaptureResult>) -> Void)?
        let keyboardTap: CFMachPort?
        lock.lock()
        (mouseCompletion, keyboardCompletion) = cancelCaptureLocked()
        keyboardTap = keyboardCaptureTap
        lock.unlock()
        if let keyboardTap { CGEvent.tapEnable(tap: keyboardTap, enable: false) }
        if let mouseCompletion { DispatchQueue.main.async { mouseCompletion(.cancelled) } }
        if let keyboardCompletion { DispatchQueue.main.async { keyboardCompletion(.cancelled) } }
        if mouseCompletion != nil || keyboardCompletion != nil { NSLog("Mousse: capture cancelled") }
        wakeTriggerTimer(at: CACurrentMediaTime())
    }

    @discardableResult
    func beginKeyboardCapture(completion: @escaping (CaptureOutcome<KeyboardCaptureResult>) -> Void)
        -> CaptureStartStatus {
        guard AccessibilityPermission.isTrusted else { return .accessibilityRequired }
        var oldMouseCompletion: ((CaptureOutcome<Int>) -> Void)?
        var oldKeyboardCompletion: ((CaptureOutcome<KeyboardCaptureResult>) -> Void)?
        lock.lock()
        guard tap != nil, let keyboardTap = keyboardCaptureTap else {
            lock.unlock()
            return .eventTapInitializing
        }
        oldMouseCompletion = captureCompletion
        oldKeyboardCompletion = keyboardCaptureCompletion
        captureKind = .keyboard
        captureCompletion = nil
        keyboardCaptureCompletion = completion
        captureDeadline = CACurrentMediaTime() + EventTapEngine.captureMaxDuration
        let deadline = captureDeadline
        lock.unlock()
        if let oldMouseCompletion { DispatchQueue.main.async { oldMouseCompletion(.cancelled) } }
        if let oldKeyboardCompletion { DispatchQueue.main.async { oldKeyboardCompletion(.cancelled) } }
        CGEvent.tapEnable(tap: keyboardTap, enable: true)
        NSLog("Mousse: keyboard capture started")
        wakeTriggerTimer(at: deadline)
        return .started
    }

    /// Update the live snapshot when config changes.
    func reload(_ config: AppConfig) {
        let captureCancellation: ((CaptureOutcome<Int>) -> Void)?
        let keyboardCaptureCancellation: ((CaptureOutcome<KeyboardCaptureResult>) -> Void)?
        lock.lock()
        // Disabling the engine or re-assigning the gesture button hides the button-up of an
        // in-flight drag from the gesture — it would stay stuck `down` and hijack every later
        // drag into Space switches. Cancel it the same way wake/device-change do.
        if (enabled && !config.enabled) || spaceDragButton != config.spaceDragButton {
            pendingDragCancel = true
        }
        pendingTriggerCancel = true
        enabled = config.enabled
        reverseScroll = config.reverseScroll
        scrollMode = config.scrollMode
        scrollSmoothness = config.scrollSmoothness
        scrollSpeed = config.scrollSpeed
        zoomSpeed = config.zoomSpeed
        edgeScrollEnabled = config.edgeScroll
        edgeScrollSpeed = config.edgeScrollSpeed
        scrollLines = config.scrollLines
        scrollAcceleration = config.scrollAcceleration
        smoothHighRes = config.smoothHighRes
        doubleClickInterval = config.doubleClickInterval
        holdDuration = config.holdDuration
        spaceDragButton = config.spaceDragButton
        spaceDragThreshold = config.spaceDragThreshold
        spaceDragReverse = config.spaceDragReverse
        spaceDragFollowFinger = config.spaceDragFollowFinger
        spaceDragLockPointer = config.spaceDragLockPointer
        excludedBundleIDs = Set(config.excludedBundleIDs).union(EventTapEngine.terminalBundleIDs)
        verticalToHorizontalBundleIDs = Set(config.verticalToHorizontalBundleIDs)
        mappingsByButton = Dictionary(grouping: config.mappings, by: \.buttonNumber).compactMapValues { mappings in
            // `.none` mappings are unconfigured placeholders — exclude them, and drop the whole
            // button group if nothing is configured yet, so the button keeps its normal behavior
            // (not swallowed) until the user picks an action. Hold-and-scroll outputs are handled
            // by `holdScroll`, not the hold timer — exclude them from `hold` as well.
            let actions = ButtonTriggerRecognizer.Actions(
                click: mappings.first(where: { $0.trigger == .click && $0.action != .none })?.action,
                doubleClick: mappings.first(where: { $0.trigger == .doubleClick && $0.action != .none })?.action,
                hold: mappings.first(where: { $0.trigger == .hold && $0.action != .none && !$0.action.isScrollOutput })?.action)
            return (actions.click != nil || actions.doubleClick != nil || actions.hold != nil)
                ? actions : nil
        }
        // Hold-and-scroll buttons: every mapping with trigger == .hold and a `.scrollOutput`
        // action, keyed by button number — each configured button works independently and no
        // other button is ever affected.
        var holdScrollMap: [Int: RemapAction.ScrollOutput] = [:]
        for m in config.mappings where m.trigger == .hold {
            if case let .scrollOutput(output) = m.action { holdScrollMap[m.buttonNumber] = output }
        }
        holdScrollByButton = holdScrollMap
        (captureCancellation, keyboardCaptureCancellation) = cancelCaptureLocked()
        let keyboardTap = keyboardCaptureTap
        lock.unlock()
        if let keyboardTap { CGEvent.tapEnable(tap: keyboardTap, enable: false) }
        if let captureCancellation { DispatchQueue.main.async { captureCancellation(.cancelled) } }
        if let keyboardCaptureCancellation { DispatchQueue.main.async { keyboardCaptureCancellation(.cancelled) } }
        wakeTriggerTimer(at: CACurrentMediaTime())
    }

    // MARK: - Tap thread

    private func threadMain() {
        let mask: CGEventMask =
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue) |
            (1 << CGEventType.otherMouseDragged.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        // tapCreate returns nil until Accessibility is granted. Retry instead of giving up, so the
        // tap comes alive the moment the user flips the toggle — no app restart needed.
        var created: CFMachPort?
        var attempts = 0
        while created == nil {
            created = CGEvent.tapCreate(tap: .cghidEventTap,
                                        place: .headInsertEventTap,
                                        options: .defaultTap,
                                        eventsOfInterest: mask,
                                        callback: eventTapCallback,
                                        userInfo: refcon)
            if created == nil {
                // Accessibility is normally granted seconds after the prompt — but it may never be.
                // Log the first failure, then at most once a minute: an unconditional 1 Hz NSLog
                // runs forever and floods the unified log for a user who simply declined.
                if attempts % 60 == 0 {
                    NSLog("Mousse: event tap not created (Accessibility not granted yet?), retrying…")
                }
                attempts += 1
                Thread.sleep(forTimeInterval: 1.0)
            }
        }
        let tap = created!
        let keyboardTap = CGEvent.tapCreate(tap: .cghidEventTap,
                                            place: .headInsertEventTap,
                                            options: .defaultTap,
                                            eventsOfInterest: 1 << CGEventType.keyDown.rawValue,
                                            callback: keyboardCaptureCallback,
                                            userInfo: refcon)
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            NSLog("Mousse: failed to create run-loop source for the event tap") // would trap below
            return
        }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        if let keyboardTap,
           let keyboardSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, keyboardTap, 0) {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), keyboardSource, .commonModes)
            CGEvent.tapEnable(tap: keyboardTap, enable: false)
        } else {
            NSLog("Mousse: keyboard capture event tap could not be created")
        }
        let triggerTimer = CFRunLoopTimerCreateWithHandler(
            kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + 86_400, 0, 0, 0
        ) { [weak self] _ in
            self?.handleButtonTriggerTimer()
        }
        // Edge-scroll ticker: ~30 Hz while the feature is enabled (the handler itself no-ops
        // instantly when it isn't). Always scheduled — toggling the setting then just flips a
        // flag; recreating timers per toggle would be needless lifecycle.
        let edgeScrollTimer = CFRunLoopTimerCreateWithHandler(
            kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + 1.0 / 30.0, 1.0 / 30.0, 0, 0
        ) { [weak self] _ in
            self?.handleEdgeScrollTick()
        }
        let runLoop = CFRunLoopGetCurrent()
        CFRunLoopAddTimer(runLoop, triggerTimer, .commonModes)
        CFRunLoopAddTimer(runLoop, edgeScrollTimer, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        lock.lock()
        self.tap = tap
        self.keyboardCaptureTap = keyboardTap
        buttonTriggerTimer = triggerTimer
        eventTapRunLoop = runLoop
        lock.unlock()
        PointerFreeze.shared.install(on: runLoop)
        CFRunLoopRun()
    }

    /// Toggle Windows-style auto-scroll mode. Called from RemapAction.post (tap thread, like every
    /// other gesture interaction) — no locking needed.
    ///
    /// Entering anchors the pointer at its current position (PointerFreeze) and converts every
    /// VIRTUAL pointer movement into scroll fed to the animator: the pointer never moves, so
    /// synthetic scroll events keep dispatching to the anchor — nested scroll areas (chat boxes,
    /// code panels) scroll correctly without per-app adaptation, and scrolling is unlimited.
    func toggleAutoScroll() {
        if autoScroll.isActive {
            PointerFreeze.shared.unfreeze()
            autoScroll.toggle()
        } else {
            let anchor = CGEvent(source: nil)?.location ?? .zero
            autoScroll.toggle()
            PointerFreeze.shared.freeze(at: anchor) { [weak self] pos in
                guard let self, self.autoScroll.isActive else { return }
                let (dx, dy) = AutoScrollController.scrollDelta(from: anchor, to: pos)
                if dx != 0 || dy != 0 {
                    // Ease through the animator (hi-res path, gain 1.0 at the default slider) so
                    // the mode scrolls as smoothly as the wheel — not per-event jumps.
                    self.scrollAnimator.addPixels(pxV: dy, pxH: dx, speed: 0.5)
                }
            }
        }
    }

    /// Edge-scroll tick (tap thread, ~30 Hz): rest the pointer on the screen edge and the page
    /// scrolls continuously. Auto-scroll no longer polls here — it anchors the pointer and is
    /// driven event-by-event through PointerFreeze.
    private func handleEdgeScrollTick() {
        lock.lock()
        let enabled = edgeScrollEnabled
        let speed = edgeScrollSpeed
        lock.unlock()
        guard enabled else { return }
        guard let loc = CGEvent(source: nil)?.location else { return }
        guard let bounds = screenBounds(at: loc) else { return }
        let delta = edgeScrollDetector.tick(pointer: loc, screenBounds: bounds,
                                            now: CACurrentMediaTime(),
                                            lastRealWheelAt: lastRealWheelAt, speed: speed)
        guard delta != 0 else { return }
        postScrollDelta(dx: 0, dy: delta)
    }

    /// Bounds of the display under `point` (nil when the lookup misses).
    private func screenBounds(at point: CGPoint) -> CGRect? {
        var display: CGDirectDisplayID = 0
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(point, 1, &display, &count) == .success, count > 0 else { return nil }
        return CGDisplayBounds(display)
    }

    /// Post a synthetic phase-less continuous pixel scroll event, tagged so the tap passes it
    /// through. Tap-thread only (called from the periodic tick).
    private func postScrollDelta(dx: Double, dy: Double) {
        guard let event = CGEvent(scrollWheelEvent2Source: scrollSource, units: .pixel,
                                  wheelCount: 2, wheel1: Int32(dy.rounded()),
                                  wheel2: Int32(dx.rounded()), wheel3: 0) else { return }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.eventSourceUserData, value: ScrollAnimator.syntheticTag)
        event.post(tap: .cghidEventTap)
    }

    private func handleButtonTriggerTimer() {
        let now = CACurrentMediaTime()
        lock.lock()
        let cancel = pendingTriggerCancel
        pendingTriggerCancel = false
        var captureCallback: ((CaptureOutcome<Int>) -> Void)?
        var keyboardCaptureCallback: ((CaptureOutcome<KeyboardCaptureResult>) -> Void)?
        var keyboardTapToDisable: CFMachPort?
        if captureKind == .mouse {
            if now >= captureDeadline {
                captureCallback = cancelCaptureLocked().0
            }
        } else if captureKind == .keyboard, now >= captureDeadline {
            keyboardCaptureCallback = keyboardCaptureCompletion
            keyboardCaptureCompletion = nil
            captureKind = .none
            keyboardTapToDisable = keyboardCaptureTap
        }
        lock.unlock()
        if let keyboardTapToDisable { CGEvent.tapEnable(tap: keyboardTapToDisable, enable: false) }
        if let captureCallback {
            DispatchQueue.main.async { captureCallback(.timedOut) }
            NSLog("Mousse: mouse capture timed out")
        }
        if let keyboardCaptureCallback {
            DispatchQueue.main.async { keyboardCaptureCallback(.timedOut) }
            NSLog("Mousse: keyboard capture timed out")
        }
        if cancel {
            buttonTriggers.cancelAll()
            scheduleButtonTriggerTimer()
            return
        }
        let output = buttonTriggers.advance(to: now)
        if output.triggered.contains(where: { $0.button == spaceDrag.button }), spaceDrag.isActive {
            spaceDrag.cancel()
        }
        post(output)
    }

    private func scheduleButtonTriggerTimer() {
        lock.lock()
        let timer = buttonTriggerTimer
        let captureTimerDeadline: Double?
        if captureKind == .mouse {
            captureTimerDeadline = captureDeadline
        } else if captureKind == .keyboard {
            captureTimerDeadline = captureDeadline
        } else {
            captureTimerDeadline = nil
        }
        let runLoop = eventTapRunLoop
        lock.unlock()
        guard let timer else { return }
        let fireDate: CFAbsoluteTime
        if let deadline = [buttonTriggers.nextDeadline, captureTimerDeadline].compactMap({ $0 }).min() {
            fireDate = CFAbsoluteTimeGetCurrent() + max(0, deadline - CACurrentMediaTime())
        } else {
            fireDate = CFAbsoluteTimeGetCurrent() + 86_400
        }
        CFRunLoopTimerSetNextFireDate(timer, fireDate)
        if let runLoop { CFRunLoopWakeUp(runLoop) }
    }

    private func wakeTriggerTimer(at deadline: Double) {
        lock.lock()
        let timer = buttonTriggerTimer
        let runLoop = eventTapRunLoop
        lock.unlock()
        guard let timer else { return }
        let fireDate = CFAbsoluteTimeGetCurrent() + max(0, deadline - CACurrentMediaTime())
        CFRunLoopTimerSetNextFireDate(timer, fireDate)
        if let runLoop { CFRunLoopWakeUp(runLoop) }
    }

    private func post(_ output: ButtonTriggerRecognizer.Output) {
        output.triggered.forEach { $0.action.post() }
        scheduleButtonTriggerTimer()
    }

    /// Called from the tap thread for every event of interest.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS disables a slow/stalled tap — re-enable it (the classic event-tap gotcha).
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock(); let tap = self.tap; lock.unlock()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.eventSourceUserData) == SmartNavigation.syntheticTag {
            return Unmanaged.passUnretained(event)
        }
        // Our own synthesized button clicks (RemapAction.clickButton) must reach the target app
        // untouched — re-mapping them would recurse. (Synthetic scroll events are handled inside
        // the scrollWheel case via the same tag.)
        if event.getIntegerValueField(.eventSourceUserData) == ScrollAnimator.syntheticTag {
            return Unmanaged.passUnretained(event)
        }

        lock.lock()
        let on = enabled
        let capturing = captureKind == .mouse
        let maps = mappingsByButton
        let reverse = reverseScroll
        let mode = scrollMode
        let smoothness = scrollSmoothness
        let speed = scrollSpeed
        let lines = scrollLines
        let accelerate = scrollAcceleration
        let smoothHiRes = smoothHighRes
        let doubleInterval = doubleClickInterval
        let holdTime = holdDuration
        let excluded = excludedBundleIDs
        let vToH = verticalToHorizontalBundleIDs
        let dragCancel = pendingDragCancel
        let triggerCancel = pendingTriggerCancel
        let cursorFlush = pendingCursorFlush
        pendingDragCancel = false
        pendingTriggerCancel = false
        pendingCursorFlush = false
        spaceDrag.button = spaceDragButton
        spaceDrag.threshold = spaceDragThreshold
        spaceDrag.reverse = spaceDragReverse
        spaceDrag.followFinger = spaceDragFollowFinger
        spaceDrag.lockPointer = spaceDragLockPointer
        holdScroll.mappings = holdScrollByButton
        lock.unlock()

        if dragCancel {
            spaceDrag.cancel()
            holdScroll.cancel()
            if autoScroll.isActive {
                PointerFreeze.shared.unfreeze() // release the anchored pointer too
                autoScroll.cancel()
            }
        } // tap thread — safe to touch the gesture states
        if cursorFlush { cursorApp.invalidate() }
        if triggerCancel {
            buttonTriggers.cancelAll()
            scheduleButtonTriggerTimer()
        }
        buttonTriggers.doubleClickInterval = doubleInterval
        buttonTriggers.holdDuration = holdTime

        if let suppressed = suppressedCaptureButton,
           type == .otherMouseDown || type == .otherMouseUp || type == .otherMouseDragged {
            let button = Int(event.getIntegerValueField(.mouseEventButtonNumber)) + 1
            if button == suppressed {
                if type == .otherMouseUp { suppressedCaptureButton = nil }
                return nil
            }
        }

        // Capture is recognized at the tap head so the physical button never reaches another app.
        if capturing {
            switch type {
            case .otherMouseDown:
                let button = Int(event.getIntegerValueField(.mouseEventButtonNumber)) + 1
                lock.lock()
                let callback = finishCaptureLocked(button)
                lock.unlock()
                if let callback { DispatchQueue.main.async { callback(.captured(button)) } }
                NSLog("Mousse: mouse button %d captured", button)
                scheduleButtonTriggerTimer()
                return nil
            case .otherMouseUp, .otherMouseDragged:
                return nil
            default: break
            }
        }

        guard on else { return Unmanaged.passUnretained(event) }

        switch type {
        case .otherMouseDown:
            let button = Int(event.getIntegerValueField(.mouseEventButtonNumber)) + 1
            // Hold-and-scroll: the button enters scroll-output mode on press — swallow the down.
            if holdScroll.handleButtonDown(buttonNumber: button) { return nil }
            guard let actions = maps[button] else {
                if spaceDrag.handleButtonDown(button) { return nil }
                return Unmanaged.passUnretained(event)
            }
            let isDragButton = button == spaceDrag.button
            let output = buttonTriggers.buttonDown(button, at: CACurrentMediaTime(), actions: actions,
                                                   deferImmediateClick: isDragButton)
            post(output)
            if output.triggered.contains(where: { $0.button == button }), isDragButton {
                spaceDrag.cancel()
            } else if isDragButton {
                _ = spaceDrag.handleButtonDown(button)
            }
            return nil

        case .otherMouseUp:
            let button = Int(event.getIntegerValueField(.mouseEventButtonNumber)) + 1
            // Hold-and-scroll release — swallow the up before anything else can react to it.
            if holdScroll.handleButtonUp(buttonNumber: button) { return nil }
            let up = spaceDrag.handleButtonUp(button)
            if up.consumed {
                if up.wasClick { post(buttonTriggers.buttonUp(button, at: CACurrentMediaTime())) }
                else {
                    buttonTriggers.cancel(button: button)
                    scheduleButtonTriggerTimer()
                }
                return nil
            }
            if maps[button] != nil {
                post(buttonTriggers.buttonUp(button, at: CACurrentMediaTime()))
                return nil
            }
            return Unmanaged.passUnretained(event)

        case .otherMouseDragged:
            // While the gesture is active, feed it both axes and swallow the drag so the motion
            // drives Spaces/Mission Control instead of moving anything underneath.
            if spaceDrag.handleDrag(deltaX: event.getDoubleValueField(.mouseEventDeltaX),
                                    deltaY: event.getDoubleValueField(.mouseEventDeltaY)) {
                if spaceDrag.hasDragged {
                    buttonTriggers.cancel(button: spaceDrag.button)
                    scheduleButtonTriggerTimer()
                }
                return nil
            }
            return Unmanaged.passUnretained(event)

        case .scrollWheel:
            // Let our own synthetic pixel events (from the animator) pass straight through.
            if event.getIntegerValueField(.eventSourceUserData) == ScrollAnimator.syntheticTag {
                return Unmanaged.passUnretained(event)
            }
            // Leave real trackpad gestures completely alone — they carry a scroll or momentum phase,
            // which a mouse wheel never does (high-resolution mice are "continuous" but phase-less, so
            // we must NOT gate on `isContinuous` here — that's what was skipping reverse on those mice).
            let phase = event.getIntegerValueField(scrollPhaseField)
            let momentumPhase = event.getIntegerValueField(scrollMomentumPhaseField)
            guard phase == 0, momentumPhase == 0 else { return Unmanaged.passUnretained(event) }

            // A real wheel input — used to reset the edge-scroll rest timer (user input first).
            lastRealWheelAt = CACurrentMediaTime()

            // Hold-and-scroll: while the configured button is held, wheel input drives the output
            // (volume ±1 per notch) instead of scrolling the page. Highest priority — before
            // modifiers, transpose and smoothing.
            if holdScroll.isActive {
                let lineV = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
                let lineH = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
                if lineV != 0 || lineH != 0 {
                    _ = holdScroll.handleScroll(lineDelta: Double(lineV != 0 ? lineV : lineH))
                    return nil
                }
            }

            let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0

            // Keyboard-modifier scrolling (-style): Cmd = pinch zoom, Ctrl = quick (half a
            // window per notch), Option = precise (a few px per notch), Shift = horizontal.
            let flags = event.flags
            let modZoom = flags.contains(.maskCommand)
            let modQuick = flags.contains(.maskControl)
            let modPrecise = flags.contains(.maskAlternate)
            let modShift = flags.contains(.maskShift)

            // Resolve the app under the cursor once (scroll targets the window under the pointer,
            // not the focused app) — for the per-app lists and the Chromium zoom workaround.
            //
            // This costs a WindowServer round trip, so only pay it when the answer can actually
            // change what we do. The exclusion list only matters where smoothing would otherwise
            // run; `excluded` is NEVER empty (the terminal IDs are always merged in), so without
            // this gate Standard mode and untouched hi-res passthrough — the two paths that do the
            // least work — were resolving the cursor's app on every event and discarding it.
            let smoothingPossible = isContinuous
                ? (smoothHiRes && (mode == .smooth || mode == .smoothStep))
                : (modQuick || modPrecise || mode == .smooth || mode == .smoothStep)
            let needsCursorID = !excluded.isEmpty || modZoom || !vToH.isEmpty || smoothingPossible
            let cursorID = needsCursorID ? cursorApp.bundleID(at: event.location) : nil
            // Exclusion wins over every Mousse scroll feature, including modifiers and axis swap.
            if EventTapEngine.isScrollExcluded(cursorID, from: excluded) {
                return Unmanaged.passUnretained(event)
            }
            // Axis-swap app (e.g. Nimble Commander's Brief panels): the wheel's vertical motion
            // should scroll HORIZONTALLY. We transpose the axes ourselves, so smoothing keeps
            // working — no need to rely on AppKit's transposition (which rejects phased gestures).
            // Shift toggles the swap (XOR): held over a normal app it scrolls horizontally, held
            // over an axis-swap app it restores vertical.
            let transpose = (cursorID.map(vToH.contains) == true) != modShift

            // Cmd+scroll → real pinch zoom (works wherever a trackpad pinch works). Consumes the
            // wheel event entirely; the pinch ends itself after a short quiet period.
            if modZoom {
                // A pinch and a glide at once is disorienting — stop any in-flight coast first
                // (idempotent no-op when nothing is gliding).
                scrollAnimator.endGestureNow()
                let dir = reverse ? -1.0 : 1.0
                let mag: Double
                if isContinuous {
                    // Point delta is pixels under BOTH driver conventions (fixedPt is fractional
                    // LINES per the CG contract, but pixels on e.g. Logitech-style drivers) — read
                    // the unambiguous field. Same 800 scale: point ≈ fixedPt on the hardware the
                    // constant was tuned on.
                    mag = Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
                               + event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)) * dir * zoomSpeed / 800.0
                } else {
                    // One notch = one comfortable zoom step ('s medium tick ÷ its 800 scale).
                    let notches = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
                                + event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
                    mag = Double(notches.signum()) * dir * 60.0 * zoomSpeed / 800.0
                }
                let chromium = EventTapEngine.chromiumBundlePrefixes
                    .contains { cursorID?.hasPrefix($0) == true }
                magnifier.feed(magnification: mag, chromiumBoost: chromium)
                return nil
            }

            // High-resolution / free-spin mice (e.g. MX Master 3) report continuous pixel deltas and,
            // on free-spin, the hardware flywheel coasts on its own. The OS already renders these
            // smoothly, so running them through our momentum engine would fight the flywheel and feel
            // floaty. Instead keep them native but honor the user's Scroll-speed slider and reverse —
            // both of which otherwise never reach a continuous mouse.
            if isContinuous {
                // High-res mice with NO flywheel (e.g. Keychron M6) report continuous pixels but scroll
                // choppily because the OS adds no momentum. When the user opts in, route their pixel
                // deltas through the same ease-to-target animator that smooths the notch path. Free-spin
                // mice (MX Master 3) should leave this OFF so we don't fight their hardware flywheel.
                let animated = mode == .smooth || mode == .smoothStep
                if smoothHiRes, animated {
                    let dir = reverse ? -1.0 : 1.0
                    // Point delta = pixels under both driver conventions; fixedPt would read as
                    // LINES (10× too slow) on contract-following drivers.
                    var pxV = Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)) * dir
                    var pxH = Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)) * dir
                    if transpose { swap(&pxV, &pxH) }
                    if pxV != 0 || pxH != 0 {
                        scrollAnimator.addPixels(pxV: pxV, pxH: pxH, speed: speed)
                        return nil // swallow; the animator drives the pixel scroll
                    }
                }
                // Any modification (slider gain, reverse, axis swap) must go out as a FRESH
                // tagged event: in-place field edits are not honored on passthrough (macOS
                // re-reads the original deltas — the same reason Standard-mode reverse posts
                // fresh events). Neutral settings pass the original through untouched.
                let gain = (speed / 0.5) * (reverse ? -1.0 : 1.0)
                if transpose || gain != 1.0 {
                    postContinuous(event, gain: gain, transpose: transpose)
                    return nil
                }
                return Unmanaged.passUnretained(event)
            }

            let dir = reverse ? -1.0 : 1.0
            var lineV = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)) * dir
            var lineH = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2)) * dir
            if transpose { swap(&lineV, &lineH) } // wheel scrolls the app horizontally

            // Resolve the glide tuning: the smoothness setting, overridden by a held modifier.
            // Quick/precise are DEFINED by their animation, so they force the glide even in
            // Standard and Smooth-step modes ( does the same). maxSens is scaled ~10% by the
            // display under the cursor so big screens fling proportionally farther.
            var profile = ScrollProfile.forSmoothness(smoothness)
            var forceGlide = false
            if modQuick {
                profile = .quick(screenSpan: screenSpan(at: event.location, vertical: lineV != 0))
                forceGlide = true
            } else if modPrecise {
                profile = .precise
                forceGlide = true
            }
            let baseline = lineV != 0 ? 1080.0 : 1920.0
            let sizeFactor = modQuick ? 1.0
                : screenSpan(at: event.location, vertical: lineV != 0) / baseline
            let sens = profile.sensitivity(slider: speed, screenSizeFactor: sizeFactor)

            // Notched mouse: Smooth and Smooth-step both drive the animator (momentum vs crisp N-line
            // step); Standard falls through to raw passthrough below.
            let animated = (mode == .smooth || mode == .smoothStep) || forceGlide
            if animated, lineV != 0 || lineH != 0 {
                scrollAnimator.addTick(lineV: lineV, lineH: lineH,
                                       stepped: mode == .smoothStep && !forceGlide, lines: lines,
                                       profile: profile, minSens: sens.minSens, maxSens: sens.maxSens,
                                       accelerate: accelerate)
                return nil // swallow; the animator drives the pixel scroll
            }
            if reverse || transpose {
                // macOS does NOT honor in-place delta edits on a passed-through wheel event — the
                // system re-reads the original kernel deltas, so editing fields in place is
                // invisible (this is why reverse worked in Smooth, which posts fresh events, but not
                // in Standard). So build a FRESH wheel event carrying the reversed and/or
                // axis-swapped line, pixel and fixed-point deltas, tag it so our tap skips it,
                // post it, and swallow the original. (`lineV`/`lineH` are already adjusted above.)
                guard let out = CGEvent(scrollWheelEvent2Source: scrollSource, units: .line,
                                        wheelCount: 2, wheel1: int32Clamped(lineV),
                                        wheel2: int32Clamped(lineH),
                                        wheel3: 0) else { return Unmanaged.passUnretained(event) }
                let sign: Int64 = reverse ? -1 : 1
                let p1 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
                let p2 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
                let f1 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
                let f2 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
                out.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: sign * (transpose ? p2 : p1))
                out.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: sign * (transpose ? p1 : p2))
                out.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Double(sign) * (transpose ? f2 : f1))
                out.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: Double(sign) * (transpose ? f1 : f2))
                out.setIntegerValueField(.eventSourceUserData, value: ScrollAnimator.syntheticTag)
                out.flags = [] // modifiers already applied upstream (Shift = the swap itself)
                out.post(tap: .cghidEventTap)
                return nil
            }
            return Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    static func isScrollExcluded(_ bundleID: String?, from excluded: Set<String>) -> Bool {
        bundleID.map(excluded.contains) == true
    }

    private func finishCaptureLocked(_ button: Int) -> ((CaptureOutcome<Int>) -> Void)? {
        captureKind = .none
        suppressedCaptureButton = button
        let completion = captureCompletion
        captureCompletion = nil
        return completion
    }

    private func cancelCaptureLocked()
        -> (((CaptureOutcome<Int>) -> Void)?,
            ((CaptureOutcome<KeyboardCaptureResult>) -> Void)?) {
        captureKind = .none
        let mouseCompletion = captureCompletion
        let keyboardCompletion = keyboardCaptureCompletion
        captureCompletion = nil
        keyboardCaptureCompletion = nil
        return (mouseCompletion, keyboardCompletion)
    }

    fileprivate func handleKeyboardCapture(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock()
            let shouldEnable = captureKind == .keyboard
            let tap = keyboardCaptureTap
            lock.unlock()
            if shouldEnable, let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        var completion: ((CaptureOutcome<KeyboardCaptureResult>) -> Void)?
        var result: KeyboardCaptureResult?
        lock.lock()
        if captureKind == .keyboard {
            completion = keyboardCaptureCompletion
            keyboardCaptureCompletion = nil
            captureKind = .none
            if keyCode != 53 {
                result = KeyboardCaptureResult(
                    keyCode: keyCode,
                    control: flags.contains(.maskControl),
                    option: flags.contains(.maskAlternate),
                    command: flags.contains(.maskCommand),
                    shift: flags.contains(.maskShift))
            }
        }
        let keyboardTap = keyboardCaptureTap
        lock.unlock()
        if let keyboardTap { CGEvent.tapEnable(tap: keyboardTap, enable: false) }
        if let completion {
            let outcome: CaptureOutcome<KeyboardCaptureResult> = result.map(CaptureOutcome.captured)
                ?? .cancelled
            DispatchQueue.main.async { completion(outcome) }
            NSLog(result == nil ? "Mousse: keyboard capture cancelled" : "Mousse: keyboard capture completed")
            return nil
        }
        return Unmanaged.passUnretained(event)
    }
}

/// Undocumented CGEvent scroll fields that distinguish a real trackpad gesture (which sets a scroll
/// or momentum phase) from a mouse wheel (which never does, even high-resolution "continuous" mice).
private let scrollPhaseField = CGEventField(rawValue: 99)!          // kCGScrollWheelEventScrollPhase
private let scrollMomentumPhaseField = CGEventField(rawValue: 123)! // kCGScrollWheelEventMomentumPhase

extension EventTapEngine {
    /// Scale a continuous (high-res) mouse's deltas by the Scroll-speed slider and flip them for
    /// reverse, in place. Neutral speed (0.5, the slider default) maps to gain 1.0 so the mouse keeps
    /// its native feel until the user actually moves the slider.
    /// Pixel span of the display under `point` — feeds screen-size sensitivity scaling and the
    /// quick-scroll window size. Falls back to the 1080p baseline when the lookup misses.
    fileprivate func screenSpan(at point: CGPoint, vertical: Bool) -> Double {
        var display: CGDirectDisplayID = 0
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(point, 1, &display, &count) == .success, count > 0 else {
            return vertical ? 1080 : 1920
        }
        return Double(vertical ? CGDisplayPixelsHigh(display) : CGDisplayPixelsWide(display))
    }

    /// Post a fresh continuous (pixel) event with the slider gain / reverse sign applied and the
    /// axes optionally swapped — for the hi-res path whenever the original can't pass through
    /// unmodified (in-place edits on a passthrough don't stick).
    fileprivate func postContinuous(_ event: CGEvent, gain: Double, transpose: Bool) {
        var pV = Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)) * gain
        var pH = Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)) * gain
        // Line/fixedPt outputs are derived from the SAME point-field pixels (sanitized: the tap
        // sees every process's synthetic scroll events, and a huge delta would trap `Int64(_:)`).
        // Reading the input's fixedPt here instead would count 10× too few lines on drivers that
        // follow the CG contract (fixedPt = fractional lines, not pixels).
        var fV = sanitizedDelta(pV)
        var fH = sanitizedDelta(pH)
        if transpose { swap(&pV, &pH); swap(&fV, &fH) }
        guard let out = CGEvent(scrollWheelEvent2Source: scrollSource, units: .pixel, wheelCount: 2,
                                wheel1: int32Clamped(pV), wheel2: int32Clamped(pH),
                                wheel3: 0) else { return }
        out.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        // Explicit line deltas (1 line ≈ 10 px) so terminals don't see a wheel line per event.
        // Carried across events, like the animator's lineCarry: slow scrolls (< 10 px/event)
        // must accumulate into whole lines or terminals would never move. Written FIRST: the
        // line-delta setter re-syncs the fixed-point/point fields to the whole-line value, so
        // the precise pixel writes must follow it (same ordering rule as ScrollAnimator.post).
        // Same field semantics as ScrollAnimator.post (mirroring real trackpad events): line
        // and fixed-point deltas are in LINE units (fixed-point = precise fractional lines,
        // integer = accumulated whole lines), point delta is in pixels. Pixels in the
        // fixed-point field read as N× too many lines and flood mouse-reporting terminals.
        // Lines are derived from the PRE-gain deltas (fV/fH carry gain already, so divide it
        // back out): the slider scales pixel motion, but the device still turned the same
        // amount, and line-based consumers should see the device's own line count.
        let lineDiv = 10 * max(abs(gain), 0.05)
        contLineCarryV += fV / lineDiv
        contLineCarryH += fH / lineDiv
        let lv = contLineCarryV.rounded(.towardZero); contLineCarryV -= lv
        let lh = contLineCarryH.rounded(.towardZero); contLineCarryH -= lh
        out.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: Int64(lv))
        out.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: Int64(lh))
        out.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: fV / lineDiv)
        out.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: fH / lineDiv)
        out.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(int32Clamped(pV)))
        out.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(int32Clamped(pH)))
        out.setIntegerValueField(.eventSourceUserData, value: ScrollAnimator.syntheticTag)
        out.flags = [] // modifiers already applied upstream (Shift = the swap itself)
        out.post(tap: .cghidEventTap)
    }
}

/// Convert a (possibly foreign/corrupt) event delta to Int32 without trapping.
private func int32Clamped(_ v: Double) -> Int32 {
    guard v.isFinite else { return 0 }
    return Int32(min(max(v, -2_147_483_647), 2_147_483_647))
}

/// Zero a non-finite delta and clamp the rest to a sane pixel range, so downstream integer
/// conversions can never trap on a corrupt foreign event.
private func sanitizedDelta(_ v: Double) -> Double {
    guard v.isFinite else { return 0 }
    return min(max(v, -1_000_000), 1_000_000)
}

/// Top-level C-compatible callback (CGEventTapCallBack). Forwards to the engine via `refcon`.
private func eventTapCallback(proxy: CGEventTapProxy,
                              type: CGEventType,
                              event: CGEvent,
                              refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let engine = Unmanaged<EventTapEngine>.fromOpaque(refcon).takeUnretainedValue()
    return engine.handle(type: type, event: event)
}

private func keyboardCaptureCallback(proxy: CGEventTapProxy,
                                     type: CGEventType,
                                     event: CGEvent,
                                     refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let engine = Unmanaged<EventTapEngine>.fromOpaque(refcon).takeUnretainedValue()
    return engine.handleKeyboardCapture(type: type, event: event)
}
