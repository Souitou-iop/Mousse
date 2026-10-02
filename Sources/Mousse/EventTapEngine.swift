import AppKit
import CoreGraphics
import Foundation
import IOKit.hid
import QuartzCore
import os

/// Owns the CGEventTap that intercepts mouse buttons and scroll, running on a dedicated
/// high-priority thread (never the main thread — a stalled main thread would time out the tap).
final class EventTapEngine {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.mousse.app",
        category: "EventTap")

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
    private var lifecycleStarted = false
    private var tapRebuildPending = false
    private var tapCreationFailed = false
    private var nextTapCreationAttemptAt = Date.distantPast
    private var lastPermissionGateState: Bool?
    private var wakeDebounceWorkItem: DispatchWorkItem?

    // Snapshot read by the tap callback thread; guarded by `lock`.
    private let lock = OSAllocatedUnfairLock()
    // Serialize physical-wheel handling with reload cancellation so an old snapshot cannot
    // restart output after reload has cancelled it. Always acquire before `lock`.
    private let scrollSessionLock = OSAllocatedUnfairLock()
    private var scrollSessionContext: ScrollSessionContext?
    private var scrollSessionBundleID: String?
    private var enabled = true
    private var scrollDeviceProfiles: [String: ScrollDeviceSettings] = [:]
    private var reverseScroll = false
    private var reverseScrollHorizontal = false
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
    private var autoScrollSpeed = 1.5
    private var autoScrollBaseSpeed = 120.0
    private var autoScrollClickDelay = AutoScrollClickDelaySetting.defaultValue
    private var showAutoScrollHUD = true
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
    private var scrollAppProfiles: [String: ScrollAppProfile] = [:]
    private var remoteDesktopBypass = true
    private var remoteDesktopBundleIDs: Set<String> = []
    private var gameBypass = true
    private var gameBundleIDs: Set<String> = []

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
    // iPhone Mirroring interprets original wheel events as touch swipes and rejects reposts.
    private static let passthroughBundleIDs: Set<String> = ["com.apple.ScreenContinuity"]
    private var verticalToHorizontalBundleIDs: Set<String> = []
    private static let chromiumBundlePrefixes = [
        "com.google.Chrome", "org.chromium.Chromium", "com.operasoftware.Opera",
        "com.microsoft.edgemac", "com.vivaldi.Vivaldi", "com.brave.Browser",
    ]
    private var buttonMappings = CompiledButtonMappings(AppConfig().mappings)
    /// Apps where the button mappings are bypassed entirely — a remapped button keeps its native
    /// behavior while the pointer is over one of these. Read on the tap thread with the rest of the
    /// per-event snapshot, resolved from the cursor app's bundle ID (same resolver as scrolling).
    private var buttonMappingExcludedBundleIDs: Set<String> = []
    private var pendingDragCancel = false // set on wake/device-change, consumed on the tap thread
    private var pendingAutoScrollCancel = false
    private var pendingTriggerCancel = false
    private var pendingCursorFlush = false
    private var eventTapRecoveryCount = 0
    private var lastEventTapRecoveryAt: Date?
    private var detectedMice: [DetectedMouse] = []
    private var lastTriggeredAction: LastTriggeredAction?
    private var autoScrollHUDGeneration: UInt64 = 0

    /// Source for fresh wheel events that need a speed gain or axis swap.
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
    private var autoScrollExitPassThrough = AutoScrollExitPassThroughTracker() // tap-thread only
    private let buttonTriggers = ButtonTriggerRecognizer()
    private var buttonTriggerTimer: CFRunLoopTimer?
    private var eventTapRunLoop: CFRunLoop?
    private let cursorApp = CursorAppResolver() // tap-thread only, like the animator
    private let screenSpans = ScreenSpanResolver() // tap-thread only; flushed with `cursorApp`

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
        lock.lock()
        guard !lifecycleStarted else {
            lock.unlock()
            return
        }
        lifecycleStarted = true
        lock.unlock()
        startTapThreadIfNeeded()

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

    private func startTapThreadIfNeeded() {
        lock.lock()
        guard thread == nil, !tapRebuildPending,
              Date() >= nextTapCreationAttemptAt else {
            lock.unlock()
            return
        }
        let t = Thread { [weak self] in self?.threadMain() }
        t.name = "com.mousse.event-tap"
        t.qualityOfService = .userInteractive
        thread = t
        tapCreationFailed = false
        lock.unlock()
        t.start()
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
        refreshDetectedMice()
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
        PointerFreeze.shared.reset()
        lock.lock()
        pendingDragCancel = true
        pendingAutoScrollCancel = true
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
        hidManager = mgr
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let opened = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        if opened != kIOReturnSuccess {
            // Non-fatal: device callbacks won't fire, so report-rate re-enumeration recovery is skipped
            // (Space/app-switch recovery is unaffected). Log so a silent failure is diagnosable.
            NSLog("Mousse: IOHIDManagerOpen failed (0x%X) — report-rate scroll recovery disabled", opened)
        }
        refreshDetectedMice()
    }

    private func refreshDetectedMice() {
        guard let hidManager,
              let devices = IOHIDManagerCopyDevices(hidManager) as? Set<IOHIDDevice> else {
            lock.lock(); detectedMice = []; lock.unlock()
            return
        }
        let mice = devices.map { device -> DetectedMouse in
            func string(_ key: CFString) -> String? {
                IOHIDDeviceGetProperty(device, key) as? String
            }
            func number(_ key: CFString) -> Int {
                (IOHIDDeviceGetProperty(device, key) as? NSNumber)?.intValue ?? 0
            }
            let product = string(kIOHIDProductKey as CFString)
            let manufacturer = string(kIOHIDManufacturerKey as CFString)
            let name: String
            if let product, let manufacturer,
               !product.localizedCaseInsensitiveContains(manufacturer) {
                name = "\(manufacturer) \(product)"
            } else {
                name = product ?? manufacturer ?? "HID Mouse"
            }
            let vendorID = number(kIOHIDVendorIDKey as CFString)
            let productID = number(kIOHIDProductIDKey as CFString)
            let locationID = number(kIOHIDLocationIDKey as CFString)
            let serial = string(kIOHIDSerialNumberKey as CFString) ?? ""
            return DetectedMouse(id: "\(vendorID):\(productID):\(locationID):\(serial)", name: name)
        }
        lock.lock(); detectedMice = DetectedMouse.deduplicated(mice); lock.unlock()
    }

    /// On wake, re-enable the tap AND rebuild the scroll animator's display link, which macOS
    /// invalidates across sleep (leaving smooth scroll dead until it eventually self-heals).
    @objc func handleWake() {
        // Debounce rapid successive screen/wake notifications (e.g. multi-display wake bursts)
        wakeDebounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.performWakeRecovery()
        }
        wakeDebounceWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
    }

    private func performWakeRecovery() {
        requestEventTapRebuild(reason: "wake or display change")
        scrollAnimator.handleWake()
        magnifier.endNow()
        requestInputCancel()
        lock.lock(); pendingCursorFlush = true; lock.unlock()
    }

    /// Re-enable the tap if macOS disabled it (e.g. across sleep/wake). Safe to call from any thread
    /// and idempotent — tapEnable on an already-enabled tap is a no-op.
    @objc func reEnableTap() {
        lock.lock()
        let tap = self.tap
        let rebuildPending = tapRebuildPending
        lock.unlock()
        guard !rebuildPending else { return }
        guard let tap else {
            if AccessibilityPermission.isTrusted { startTapThreadIfNeeded() }
            return
        }
        if !CGEvent.tapIsEnabled(tap: tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
            if CGEvent.tapIsEnabled(tap: tap) {
                recordEventTapRecovery()
                Self.logger.notice("Event tap was disabled and has been re-enabled")
            } else {
                requestEventTapRebuild(reason: "tapEnable did not restore the tap")
            }
        }
    }

    private func requestEventTapRebuild(reason: String) {
        lock.lock()
        guard !tapRebuildPending else {
            lock.unlock()
            return
        }
        tapRebuildPending = true
        tapCreationFailed = false
        guard let runLoop = eventTapRunLoop else {
            tapRebuildPending = false
            lock.unlock()
            if AccessibilityPermission.isTrusted { startTapThreadIfNeeded() }
            return
        }
        lock.unlock()

        Self.logger.error("Rebuilding event tap: \(reason, privacy: .public)")
        // A queued stop survives the gap before CFRunLoopRun starts.
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
        CFRunLoopWakeUp(runLoop)
    }

    private func recordEventTapRecovery() {
        lock.lock()
        eventTapRecoveryCount += 1
        lastEventTapRecoveryAt = Date()
        lock.unlock()
    }

    func diagnosticsSnapshot(accessibilityTrusted: Bool = AccessibilityPermission.isTrusted,
                             inputMonitoringTrusted: Bool = InputMonitoringPermission.isTrusted,
                             pointerBundleID: String? = nil,
                             now: Date = Date()) -> EngineDiagnosticsSnapshot {
        lock.lock()
        let tap = self.tap
        let engineEnabled = enabled
        let recoveryCount = eventTapRecoveryCount
        let lastRecoveryAt = lastEventTapRecoveryAt
        let rebuildPending = tapRebuildPending
        let creationFailed = tapCreationFailed
        let detectedMice = self.detectedMice
        let lastAction = lastTriggeredAction
        lock.unlock()

        let health = EventTapHealth.resolve(
            accessibilityTrusted: accessibilityTrusted,
            hasTap: tap != nil,
            tapEnabled: tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false,
            rebuildPending: rebuildPending,
            creationFailed: creationFailed,
            lastRecoveryAt: lastRecoveryAt,
            now: now)
        return EngineDiagnosticsSnapshot(
            accessibilityTrusted: accessibilityTrusted,
            inputMonitoringTrusted: inputMonitoringTrusted,
            engineEnabled: engineEnabled,
            eventTapHealth: health,
            recoveryCount: recoveryCount,
            lastRecoveryAt: lastRecoveryAt,
            detectedMice: detectedMice,
            pointerBundleID: pointerBundleID,
            lastAction: lastAction)
    }

    /// Periodically poll for a silently-disabled tap. 2s is invisible to the user yet costs nothing.
    private func startWatchdog() {
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.reEnableTap()
            self?.refreshPermissionState()
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    private func refreshPermissionState() {
        let granted = MoussePermissionGate.isGranted
        lock.lock()
        let changed = lastPermissionGateState != granted
        lastPermissionGateState = granted
        lock.unlock()
        guard changed else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.reload(ConfigStore.shared.config)
        }
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
        pendingAutoScrollCancel = true
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
        scrollSessionLock.lock()
        defer { scrollSessionLock.unlock() }
        lock.lock()
        let newAppProfiles = Dictionary(config.scrollAppProfiles.map { ($0.bundleID, $0) },
                                        uniquingKeysWith: { _, last in last })
        let newExcluded = Set(config.excludedBundleIDs).union(Self.terminalBundleIDs)
        var scrollRulesChanged = false
        if let context = scrollSessionContext {
            let bundle = scrollSessionBundleID
            let oldApp = Self.resolveScrollAppSettings(bundleID: bundle, profiles: scrollAppProfiles,
                excluded: excludedBundleIDs, globalReverse: context.settings.reverseScroll,
                globalReverseHorizontal: context.settings.reverseScrollHorizontal, mode: context.settings.scrollMode)
            let newApp = Self.resolveScrollAppSettings(bundleID: bundle, profiles: newAppProfiles,
                excluded: newExcluded, globalReverse: context.settings.reverseScroll,
                globalReverseHorizontal: context.settings.reverseScrollHorizontal, mode: context.settings.scrollMode)
            scrollRulesChanged = oldApp != newApp
                || bundle.map { verticalToHorizontalBundleIDs.contains($0) != config.verticalToHorizontalBundleIDs.contains($0) } == true
                || Self.isScrollSafetyBypassed(bundleID: bundle, remoteDesktopBypass: remoteDesktopBypass,
                    remoteDesktopBundles: remoteDesktopBundleIDs, gameBypass: gameBypass, gameBundles: gameBundleIDs)
                    != Self.isScrollSafetyBypassed(bundleID: bundle, remoteDesktopBypass: config.remoteDesktopBypass,
                    remoteDesktopBundles: Set(config.remoteDesktopBundleIDs), gameBypass: config.gameBypass,
                    gameBundles: Set(config.gameBundleIDs))
        }
        // Disabling the engine or re-assigning the gesture button hides the button-up of an
        // in-flight drag from the gesture — it would stay stuck `down` and hijack every later
        // drag into Space switches. Cancel it the same way wake/device-change do.
        let effectiveEnabled = config.enabled && MoussePermissionGate.isGranted
        let cancelWheel = Self.reloadInvalidatesScrollContext(scrollSessionContext, config: config)
            || (scrollSessionContext != nil && (scrollRulesChanged || (enabled && !effectiveEnabled)))
        if (enabled && !effectiveEnabled) || spaceDragButton != config.spaceDragButton {
            pendingDragCancel = true
            pendingAutoScrollCancel = true
        }
        pendingTriggerCancel = true
        enabled = effectiveEnabled
        scrollDeviceProfiles = [:]
        for profile in config.deviceProfiles where scrollDeviceProfiles[profile.id] == nil {
            scrollDeviceProfiles[profile.id] = profile.settings
        }
        reverseScroll = config.reverseScroll
        reverseScrollHorizontal = config.reverseScrollHorizontal
        scrollMode = config.scrollMode
        scrollSmoothness = config.scrollSmoothness
        scrollSpeed = config.scrollSpeed
        zoomSpeed = config.zoomSpeed
        edgeScrollEnabled = config.edgeScroll
        edgeScrollSpeed = config.edgeScrollSpeed
        autoScrollSpeed = config.autoScrollSpeed
        autoScrollBaseSpeed = config.autoScrollBaseSpeed
        autoScrollClickDelay = config.autoScrollClickDelay
        let autoScrollHUDVisibilityChanged = showAutoScrollHUD != config.showAutoScrollHUD
        let shouldHideAutoScrollHUD = showAutoScrollHUD && !config.showAutoScrollHUD
        if autoScrollHUDVisibilityChanged { autoScrollHUDGeneration &+= 1 }
        let hudGeneration = autoScrollHUDGeneration
        showAutoScrollHUD = config.showAutoScrollHUD
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
        scrollAppProfiles = newAppProfiles
        verticalToHorizontalBundleIDs = Set(config.verticalToHorizontalBundleIDs)
        remoteDesktopBypass = config.remoteDesktopBypass
        remoteDesktopBundleIDs = Set(config.remoteDesktopBundleIDs)
        gameBypass = config.gameBypass
        gameBundleIDs = Set(config.gameBundleIDs)
        buttonMappings = CompiledButtonMappings(config.mappings)
        buttonMappingExcludedBundleIDs = Set(config.buttonMappingExcludedBundleIDs)
        (captureCancellation, keyboardCaptureCancellation) = cancelCaptureLocked()
        let keyboardTap = keyboardCaptureTap
        lock.unlock()
        if cancelWheel {
            scrollAnimator.endGestureNow()
            magnifier.endWheelZoomNow()
            scrollSessionContext = nil
            scrollSessionBundleID = nil
        }
        if shouldHideAutoScrollHUD {
            DispatchQueue.main.async {
                AutoScrollHUDController.shared.hide(generation: hudGeneration)
            }
        }
        if let keyboardTap { CGEvent.tapEnable(tap: keyboardTap, enable: false) }
        if let captureCancellation { DispatchQueue.main.async { captureCancellation(.cancelled) } }
        if let keyboardCaptureCancellation { DispatchQueue.main.async { keyboardCaptureCancellation(.cancelled) } }
        wakeTriggerTimer(at: CACurrentMediaTime())
    }

    // MARK: - Tap thread

    private func threadMain() {
        let mask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue) |
            (1 << CGEventType.otherMouseDragged.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue) |
            (1 << CGEventType.keyDown.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        // Try briefly, then yield the thread. The main-thread watchdog starts a fresh attempt after
        // permission changes, instead of keeping a high-priority thread in an infinite sleep loop.
        var created: CFMachPort?
        let delays: [TimeInterval] = [0, 0.1, 0.25, 0.5, 1.0]
        for delay in delays {
            guard AccessibilityPermission.isTrusted else { break }
            if delay > 0 { Thread.sleep(forTimeInterval: delay) }
            created = CGEvent.tapCreate(tap: .cghidEventTap,
                                        place: .headInsertEventTap,
                                        options: .defaultTap,
                                        eventsOfInterest: mask,
                                        callback: eventTapCallback,
                                        userInfo: refcon)
            if created != nil { break }
        }
        guard let tap = created else {
            lock.lock()
            if thread === Thread.current {
                thread = nil
                let trusted = AccessibilityPermission.isTrusted
                tapCreationFailed = trusted
                nextTapCreationAttemptAt = trusted
                    ? Date().addingTimeInterval(1.0) : .distantPast
            }
            lock.unlock()
            Self.logger.error("Event tap creation failed; waiting before the next attempt")
            return
        }
        let keyboardTap = CGEvent.tapCreate(tap: .cghidEventTap,
                                            place: .headInsertEventTap,
                                            options: .defaultTap,
                                            eventsOfInterest: 1 << CGEventType.keyDown.rawValue,
                                            callback: keyboardCaptureCallback,
                                            userInfo: refcon)
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            NSLog("Mousse: failed to create run-loop source for the event tap") // would trap below
            lock.lock()
            if thread === Thread.current {
                thread = nil
                tapCreationFailed = true
                nextTapCreationAttemptAt = Date().addingTimeInterval(1.0)
            }
            lock.unlock()
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            if let keyboardTap {
                CGEvent.tapEnable(tap: keyboardTap, enable: false)
                CFMachPortInvalidate(keyboardTap)
            }
            return
        }
        let runLoop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(runLoop, source, .commonModes)
        var keyboardSource: CFRunLoopSource?
        if let keyboardTap,
           let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, keyboardTap, 0) {
            keyboardSource = src
            CFRunLoopAddSource(runLoop, src, .commonModes)
            CGEvent.tapEnable(tap: keyboardTap, enable: false)
        } else {
            NSLog("Mousse: keyboard capture event tap could not be created")
        }
        let triggerTimer = CFRunLoopTimerCreateWithHandler(
            kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + 86_400, 86_400, 0, 0
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
        CFRunLoopAddTimer(runLoop, triggerTimer, .commonModes)
        CFRunLoopAddTimer(runLoop, edgeScrollTimer, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        lock.lock()
        self.tap = tap
        self.keyboardCaptureTap = keyboardTap
        buttonTriggerTimer = triggerTimer
        eventTapRunLoop = runLoop
        tapCreationFailed = false
        nextTapCreationAttemptAt = .distantPast
        lock.unlock()
        PointerFreeze.shared.install(on: runLoop)
        CFRunLoopRun()

        // Clean up the event tap and sources explicitly so WindowServer does not leave orphaned hooks
        PointerFreeze.shared.uninstall(from: runLoop)
        CFRunLoopRemoveTimer(runLoop, triggerTimer, .commonModes)
        CFRunLoopRemoveTimer(runLoop, edgeScrollTimer, .commonModes)
        CFRunLoopRemoveSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        if let keyboardTap {
            if let keyboardSource {
                CFRunLoopRemoveSource(runLoop, keyboardSource, .commonModes)
            }
            CGEvent.tapEnable(tap: keyboardTap, enable: false)
            CFMachPortInvalidate(keyboardTap)
        }

        lock.lock()
        let shouldRestart = tapRebuildPending
        if thread === Thread.current {
            self.tap = nil
            keyboardCaptureTap = nil
            buttonTriggerTimer = nil
            eventTapRunLoop = nil
            thread = nil
            tapRebuildPending = false
        }
        lock.unlock()
        if shouldRestart {
            recordEventTapRecovery()
            startTapThreadIfNeeded()
        }
    }

    /// Toggle Windows-style auto-scroll mode. Called from RemapAction.post (tap thread, like every
    /// other gesture interaction) — no locking needed. The pointer stays free; the mode is driven
    /// by the pointer's offset from the anchor on the periodic tick (see `handleEdgeScrollTick`).
    func toggleAutoScroll() {
        if autoScroll.isActive {
            cancelAutoScroll()
        } else {
            lock.lock()
            autoScrollHUDGeneration &+= 1
            lock.unlock()
            autoScroll.toggle()
        }
    }

    private func cancelAutoScroll() {
        guard autoScroll.isActive else { return }
        autoScroll.cancel()
        lock.lock()
        autoScrollHUDGeneration &+= 1
        let generation = autoScrollHUDGeneration
        lock.unlock()
        DispatchQueue.main.async {
            AutoScrollHUDController.shared.hide(generation: generation)
        }
    }

    /// Edge-scroll + auto-scroll tick (tap thread, ~30 Hz). Auto-scroll scrolls continuously
    /// toward the pointer's offset from its anchor; edge scrolling rests the pointer on the
    /// screen edge instead. Both feed the animator for smooth output.
    private func handleEdgeScrollTick() {
        lock.lock()
        let engineEnabled = enabled
        let autoSpeed = autoScrollSpeed
        let autoBaseSpeed = autoScrollBaseSpeed
        let showHUD = showAutoScrollHUD
        let edgeEnabled = edgeScrollEnabled
        let edgeSpeed = edgeScrollSpeed
        let pendingAutoCancel = pendingAutoScrollCancel
        let hudGeneration = autoScrollHUDGeneration
        pendingAutoScrollCancel = false
        lock.unlock()

        if pendingAutoCancel { cancelAutoScroll() }

        if let deadline = buttonTriggers.nextDeadline, CACurrentMediaTime() >= deadline {
            handleButtonTriggerTimer()
        }

        // The menu-bar switch is the master kill switch. Periodic modes do not receive another
        // physical event to cancel themselves, so stop them on their own run-loop tick.
        guard engineEnabled else {
            cancelAutoScroll()
            edgeScrollDetector.reset()
            return
        }

        // Auto-scroll first: it is a user-initiated mode and independent of the edge-scroll
        // setting. The pointer is free — offset from the anchor drives direction AND speed, and
        // scrolling continues while the offset persists (Windows-style).
        if autoScroll.isActive {
            if let loc = CGEvent(source: nil)?.location {
                let (dx, dy) = autoScroll.tick(pointer: loc, now: CACurrentMediaTime(),
                                                speed: autoSpeed, baseSpeed: autoBaseSpeed)
                if dx != 0 || dy != 0 {
                    // Ease through the animator (hi-res path, gain 1.0 at the default slider) so
                    // the mode scrolls as smoothly as the wheel — not per-tick pixel jumps.
                    scrollAnimator.addPixels(pxV: dy, pxH: dx, speed: 0.5)
                }
                if showHUD, let anchor = autoScroll.anchor {
                    AutoScrollHUDController.shared.enqueueUpdate(
                        anchor: anchor, speed: autoSpeed,
                        baseSpeed: autoBaseSpeed, generation: hudGeneration)
                }
            }
        }
        guard edgeEnabled else {
            edgeScrollDetector.reset()
            return
        }
        guard let loc = CGEvent(source: nil)?.location else { return }
        guard let bounds = screenBounds(at: loc) else { return }
        let delta = edgeScrollDetector.tick(pointer: loc, screenBounds: bounds,
                                            now: CACurrentMediaTime(),
                                            lastRealWheelAt: lastRealWheelAt, speed: edgeSpeed)
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

    static func buttonClickPolicy(actions: ButtonTriggerRecognizer.Actions,
                                  isDragButton: Bool,
                                  autoScrollClickDelay: Double)
        -> ButtonTriggerRecognizer.ClickPolicy {
        if actions.click == .autoScroll {
            return .confirmed(delay: autoScrollClickDelay)
        }
        return isDragButton ? .deferredUntilRelease : .automatic
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
        if let last = LastTriggeredAction.latest(in: output, at: Date()) {
            lock.lock()
            lastTriggeredAction = last
            lock.unlock()
        }
        output.triggered.forEach { $0.action.post() }
        scheduleButtonTriggerTimer()
    }

    /// Called from the tap thread for every event of interest.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS disables a slow/stalled tap — re-enable it (the classic event-tap gotcha).
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock(); let tap = self.tap; lock.unlock()
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
                if CGEvent.tapIsEnabled(tap: tap) {
                    recordEventTapRecovery()
                } else {
                    requestEventTapRebuild(reason: "system-disabled tap could not be re-enabled")
                }
            }
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

        let isScroll = type == .scrollWheel
        if isScroll { scrollSessionLock.lock() }
        defer { if isScroll { scrollSessionLock.unlock() } }

        lock.lock()
        let on = enabled
        let capturing = captureKind == .mouse
        let mappings = buttonMappings
        let mappingExcluded = buttonMappingExcludedBundleIDs
        // Non-wheel callbacks (especially high-rate drags) do not read or retain scroll state.
        // Keep the wheel snapshot under the same lock as the shared button/cancellation state.
        let deviceProfiles = isScroll ? scrollDeviceProfiles : [:]
        var globalSettings = ScrollDeviceSettings()
        if isScroll {
            globalSettings.reverseScroll = reverseScroll
            globalSettings.reverseScrollHorizontal = reverseScrollHorizontal
            globalSettings.scrollMode = scrollMode
            globalSettings.scrollSmoothness = scrollSmoothness
            globalSettings.scrollSpeed = scrollSpeed
            globalSettings.scrollLines = scrollLines
            globalSettings.scrollAcceleration = scrollAcceleration
            globalSettings.smoothHighRes = smoothHighRes
            globalSettings.zoomSpeed = zoomSpeed
        }
        let doubleInterval = doubleClickInterval
        let holdTime = holdDuration
        let autoClickDelay = autoScrollClickDelay
        let excluded = isScroll ? excludedBundleIDs : []
        let appScrollProfiles = isScroll ? scrollAppProfiles : [:]
        let vToH = isScroll ? verticalToHorizontalBundleIDs : []
        let rdBypass = remoteDesktopBypass
        let rdBundles = remoteDesktopBundleIDs
        let gBypass = gameBypass
        let gBundles = gameBundleIDs
        let dragCancel = pendingDragCancel
        let autoScrollCancel = pendingAutoScrollCancel
        let triggerCancel = pendingTriggerCancel
        let cursorFlush = pendingCursorFlush
        pendingDragCancel = false
        pendingAutoScrollCancel = false
        pendingTriggerCancel = false
        pendingCursorFlush = false
        spaceDrag.button = spaceDragButton
        spaceDrag.threshold = spaceDragThreshold
        spaceDrag.reverse = spaceDragReverse
        spaceDrag.followFinger = spaceDragFollowFinger
        spaceDrag.lockPointer = spaceDragLockPointer
        lock.unlock()

        let maps = mappings.actionsByButton
        holdScroll.mappings = mappings.holdScrollByButton

        if dragCancel {
            spaceDrag.cancel()
            holdScroll.cancel()
        } // tap thread — safe to touch the gesture states
        if autoScrollCancel || dragCancel {
            cancelAutoScroll()
            autoScrollExitPassThrough.reset()
        }
        if cursorFlush { // tap thread — both resolvers' caches live there
            cursorApp.invalidate()
            screenSpans.invalidate()
        }
        if triggerCancel {
            buttonTriggers.cancelAll()
            scheduleButtonTriggerTimer()
        }
        buttonTriggers.doubleClickInterval = doubleInterval
        buttonTriggers.holdDuration = holdTime

        if type == .otherMouseUp || type == .otherMouseDragged {
            let button = Int(event.getIntegerValueField(.mouseEventButtonNumber)) + 1
            if autoScrollExitPassThrough.shouldPass(type: type, button: button) {
                return Unmanaged.passUnretained(event)
            }
        }

        let exitDecision = AutoScrollExitPolicy.decision(
            isActive: autoScroll.isActive,
            type: type,
            keyCode: type == .keyDown
                ? UInt16(event.getIntegerValueField(.keyboardEventKeycode)) : nil,
            scrollPhase: type == .scrollWheel
                ? event.getIntegerValueField(scrollPhaseField) : 0,
            momentumPhase: type == .scrollWheel
                ? event.getIntegerValueField(scrollMomentumPhaseField) : 0)
        switch exitDecision {
        case .cancelAndConsume:
            cancelAutoScroll()
            return nil
        case .cancelAndPassThrough:
            cancelAutoScroll()
            if type == .otherMouseDown {
                let button = Int(event.getIntegerValueField(.mouseEventButtonNumber)) + 1
                autoScrollExitPassThrough.begin(button: button)
            }
            return Unmanaged.passUnretained(event)
        case .cancelAndContinue:
            cancelAutoScroll()
        case .none:
            break
        }

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

        if (type == .otherMouseDown || type == .otherMouseUp || type == .otherMouseDragged) && (rdBypass || gBypass) {
            let cursorID = cursorApp.bundleID(at: event.location)
            if rdBypass, let id = cursorID, rdBundles.contains(id) {
                return Unmanaged.passUnretained(event)
            }
            if gBypass, let id = cursorID, gBundles.contains(id) {
                return Unmanaged.passUnretained(event)
            }
        }

        // Per-app button-mapping exclusion (apps in `buttonMappingExcludedBundleIDs` keep the
        // button's native behavior). Scoped to the remappable button stream only; the cursor app
        // is resolved only when the list is non-empty.
        switch type {
        case .otherMouseDown, .otherMouseUp, .otherMouseDragged:
            if Self.isButtonMappingBypassed(
                bundleID: mappingExcluded.isEmpty ? nil : cursorApp.bundleID(at: event.location),
                excluded: mappingExcluded) {
                return Unmanaged.passUnretained(event)
            }
        default:
            break
        }

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
            let clickPolicy = Self.buttonClickPolicy(
                actions: actions, isDragButton: isDragButton,
                autoScrollClickDelay: autoClickDelay)
            let output = buttonTriggers.buttonDown(button, at: CACurrentMediaTime(), actions: actions,
                                                   clickPolicy: clickPolicy)
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
            if maps[button] != nil || buttonTriggers.isTracking(button) {
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
            guard Self.isPhysicalWheel(event) else { return Unmanaged.passUnretained(event) }

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

            let deviceKey = DeviceTracker.shared.activeDeviceKey()
            let effective = Self.resolveDeviceScrollSettings(activeKey: deviceKey,
                                                            profiles: deviceProfiles, global: globalSettings)
            if Self.updateScrollContext(&scrollSessionContext, deviceKey: deviceKey, settings: effective) {
                scrollAnimator.endGestureNow()
                magnifier.endWheelZoomNow()
            }
            let globalReverse = effective.reverseScroll
            let globalReverseHorizontal = effective.reverseScrollHorizontal
            let mode = effective.scrollMode
            let smoothness = effective.scrollSmoothness
            let speed = effective.scrollSpeed
            let lines = effective.scrollLines
            let accelerate = effective.scrollAcceleration
            let smoothHiRes = effective.smoothHighRes
            let zoomSpeed = effective.zoomSpeed
            if mode == .native {
                scrollAnimator.endGestureNow()
                magnifier.endWheelZoomNow()
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
            let needsCursorID = !excluded.isEmpty || !appScrollProfiles.isEmpty
                || modZoom || !vToH.isEmpty || smoothingPossible || rdBypass || gBypass
            let cursorID = needsCursorID ? cursorApp.bundleID(at: event.location) : nil
            scrollSessionBundleID = cursorID
            if Self.isScrollSafetyBypassed(bundleID: cursorID, remoteDesktopBypass: rdBypass,
                                           remoteDesktopBundles: rdBundles, gameBypass: gBypass,
                                           gameBundles: gBundles) {
                return Unmanaged.passUnretained(event)
            }
            let appSettings = EventTapEngine.resolveScrollAppSettings(
                bundleID: cursorID,
                profiles: appScrollProfiles,
                excluded: excluded,
                globalReverse: globalReverse,
                globalReverseHorizontal: globalReverseHorizontal, mode: mode)
            if mode == .native {
                return Unmanaged.passUnretained(Self.applyNativeWheel(event, settings: appSettings))
            }
            // Apply direction to the physical input axes before Shift/app transposition.
            Self.reverseScrollInPlace(event, vertical: appSettings.reverseScroll,
                                      horizontal: appSettings.reverseScrollHorizontal)
            // The app switches are independent. With only reverse enabled, preserve the
            // native wheel stream and apply just its direction; do not enable smoothing, speed,
            // acceleration, zoom, modifiers or axis swapping.
            if !appSettings.mousseScrollEnabled {
                return Unmanaged.passUnretained(event)
            }
            // Axis-swap app (e.g. Nimble Commander's Brief panels): the wheel's vertical motion
            // should scroll HORIZONTALLY. We transpose the axes ourselves, so smoothing keeps
            // working — no need to rely on AppKit's transposition (which rejects phased gestures).
            // Shift toggles the swap (XOR): held over a normal app it scrolls horizontally, held
            // over an axis-swap app it restores vertical.
            let transpose = Self.shouldTransposeScroll(appTransposes: cursorID.map(vToH.contains) == true,
                                                      shift: modShift)

            // Cmd+scroll → real pinch zoom (works wherever a trackpad pinch works). Consumes the
            // wheel event entirely; the pinch ends itself after a short quiet period.
            if modZoom {
                // A pinch and a glide at once is disorienting — stop any in-flight coast first
                // (idempotent no-op when nothing is gliding).
                scrollAnimator.endGestureNow()
                let mag: Double
                if isContinuous {
                    // Point delta is pixels under BOTH driver conventions (fixedPt is fractional
                    // LINES per the CG contract, but pixels on e.g. Logitech-style drivers) — read
                    // the unambiguous field. Same 800 scale: point ≈ fixedPt on the hardware the
                    // constant was tuned on.
                    mag = (Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
                               + Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2))) * zoomSpeed / 800.0
                } else {
                    // One notch = one comfortable zoom step ('s medium tick ÷ its 800 scale).
                    let notches = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
                                + Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
                    mag = (notches == 0 ? 0 : (notches > 0 ? 1.0 : -1.0)) * 60.0 * zoomSpeed / 800.0
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
                    // Point delta = pixels under both driver conventions; fixedPt would read as
                    // LINES (10× too slow) on contract-following drivers.
                    var pxV = Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
                    var pxH = Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2))
                    if transpose { swap(&pxV, &pxH) }
                    if pxV != 0 || pxH != 0 {
                        scrollAnimator.addPixels(pxV: pxV, pxH: pxH, speed: speed)
                        return nil // swallow; the animator drives the pixel scroll
                    }
                }
                let gain = speed / 0.5
                if transpose || speed != 0.5 {
                    postContinuous(event, gain: gain, transpose: transpose)
                    return nil
                }
                return Unmanaged.passUnretained(event)
            }

            var lineV = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
            var lineH = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
            if transpose { swap(&lineV, &lineH) } // wheel scrolls the app horizontally

            // Quick/precise force a glide even in Standard and Smooth-step. Resolve its tuning
            // only when a nonzero tick will actually reach the animator; plain Standard and empty
            // wheel events need no display-span lookup or sensitivity calculation.
            let forceGlide = modQuick || modPrecise
            let animated = mode.isSmooth || forceGlide
            if animated, lineV != 0 || lineH != 0 {
                var profile = ScrollProfile.forSmoothness(smoothness)
                if modQuick {
                    profile = .quick(screenSpan: screenSpans.span(at: event.location, vertical: lineV != 0))
                } else if modPrecise {
                    profile = .precise
                }
                let baseline = lineV != 0 ? 1080.0 : 1920.0
                let sizeFactor = modQuick ? 1.0
                    : screenSpans.span(at: event.location, vertical: lineV != 0) / baseline
                let sens = profile.sensitivity(slider: speed, screenSizeFactor: sizeFactor)

                scrollAnimator.addTick(lineV: lineV, lineH: lineH,
                                       stepped: mode == .smoothStep && !forceGlide, lines: lines,
                                       profile: profile, minSens: sens.minSens, maxSens: sens.maxSens,
                                       accelerate: accelerate)
                return nil // swallow; the animator drives the pixel scroll
            }
            if transpose {
                postNativeScroll(event, transpose: true)
                return nil
            }
            return Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// Whether the button mappings should be bypassed for this cursor app. Pure so the tap thread
    /// and the tests share one definition. A nil bundle ID (no resolvable app — desktop, menu bar,
    /// a not-yet-resolved window) is never bypassed: only an explicit match disables the remaps.
    static func isButtonMappingBypassed(bundleID: String?, excluded: Set<String>) -> Bool {
        guard let bundleID else { return false }
        return excluded.contains(bundleID)
    }

    struct ScrollSessionContext: Equatable {
        let deviceKey: String?
        let settings: ScrollDeviceSettings
    }

    /// Used by the physical-wheel path; a new device must not inherit another device's tick history.
    static func updateScrollContext(_ context: inout ScrollSessionContext?, deviceKey: String?,
                                    settings: ScrollDeviceSettings) -> Bool {
        let next = ScrollSessionContext(deviceKey: deviceKey, settings: settings)
        let changed = context != nil && context != next
        context = next
        return changed
    }

    static func reloadInvalidatesScrollContext(_ context: ScrollSessionContext?, config: AppConfig) -> Bool {
        guard let context else { return false }
        let settings = context.deviceKey.flatMap { key in config.deviceProfiles.first { $0.id == key }?.settings }
            ?? config.scrollSettings
        return settings != context.settings
    }

    static func resolveDeviceScrollSettings(activeKey: String?,
                                            profiles: [String: ScrollDeviceSettings],
                                            global: ScrollDeviceSettings) -> ScrollDeviceSettings {
        activeKey.flatMap { profiles[$0] } ?? global
    }

    static func shouldTransposeScroll(appTransposes: Bool, shift: Bool) -> Bool {
        appTransposes != shift
    }

    struct ResolvedScrollAppSettings: Equatable {
        let mousseScrollEnabled: Bool
        let reverseScroll: Bool
        var reverseScrollHorizontal: Bool = false
    }

    static func resolveScrollAppSettings(
        bundleID: String?,
        profiles: [String: ScrollAppProfile],
        excluded: Set<String>,
        globalReverse: Bool,
        globalReverseHorizontal: Bool? = nil,
        mode: ScrollMode = .standard
    ) -> ResolvedScrollAppSettings {
        guard let bundleID else {
            return ResolvedScrollAppSettings(
                mousseScrollEnabled: mode != .native, reverseScroll: globalReverse,
                reverseScrollHorizontal: globalReverseHorizontal ?? globalReverse)
        }
        // Terminal emulators remain hard exclusions because phased/synthetic scrolling can break
        // their alternate-screen and TUI input handling.
        if terminalBundleIDs.contains(bundleID) {
            return ResolvedScrollAppSettings(mousseScrollEnabled: false, reverseScroll: false)
        }
        if mode == .native {
            return ResolvedScrollAppSettings(mousseScrollEnabled: false, reverseScroll: globalReverse,
                reverseScrollHorizontal: globalReverseHorizontal ?? globalReverse)
        }
        let requiresOriginalEvent = passthroughBundleIDs.contains(bundleID)
        if let profile = profiles[bundleID] {
            return ResolvedScrollAppSettings(
                mousseScrollEnabled: profile.mousseScrollEnabled && !requiresOriginalEvent,
                reverseScroll: profile.reverseScroll,
                reverseScrollHorizontal: profile.reverseScrollHorizontal)
        }
        if excluded.contains(bundleID) {
            return ResolvedScrollAppSettings(mousseScrollEnabled: false, reverseScroll: false)
        }
        return ResolvedScrollAppSettings(
            mousseScrollEnabled: !requiresOriginalEvent, reverseScroll: globalReverse,
            reverseScrollHorizontal: globalReverseHorizontal ?? globalReverse)
    }

    static func isPhysicalWheel(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(scrollPhaseField) == 0
            && event.getIntegerValueField(scrollMomentumPhaseField) == 0
    }

    static func isScrollSafetyBypassed(bundleID: String?, remoteDesktopBypass: Bool,
                                      remoteDesktopBundles: Set<String>, gameBypass: Bool,
                                      gameBundles: Set<String>) -> Bool {
        guard let bundleID else { return false }
        return (remoteDesktopBypass && remoteDesktopBundles.contains(bundleID))
            || (gameBypass && gameBundles.contains(bundleID))
    }

    /// Returns the exact original event: no repost, tag, modifier clearing or axis swap.
    static func applyNativeWheel(_ event: CGEvent, settings: ResolvedScrollAppSettings) -> CGEvent {
        guard isPhysicalWheel(event) else { return event }
        reverseScrollInPlace(event, vertical: settings.reverseScroll,
                             horizontal: settings.reverseScrollHorizontal)
        return event
    }

    static func reverseScrollInPlace(_ event: CGEvent, vertical: Bool = true,
                                     horizontal: Bool = true, transpose: Bool = false) {
        guard vertical || horizontal || transpose else { return }
        let lines: [CGEventField] = [.scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2]
        let fixed: [CGEventField] = [.scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2]
        let points: [CGEventField] = [.scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2]
        let signs: [Int64] = [vertical ? -1 : 1, horizontal ? -1 : 1]
        let lineValues = lines.enumerated().map { event.getIntegerValueField($0.element) &* signs[$0.offset] }
        let fixedValues = fixed.enumerated().map { event.getDoubleValueField($0.element) * Double(signs[$0.offset]) }
        let pointValues = points.enumerated().map { event.getIntegerValueField($0.element) &* signs[$0.offset] }
        for axis in 0..<2 {
            let input = transpose ? 1 - axis : axis
            // Line setters rewrite precise fields; snapshots and write order preserve them.
            event.setIntegerValueField(lines[axis], value: lineValues[input])
            event.setDoubleValueField(fixed[axis], value: fixedValues[input])
            event.setIntegerValueField(points[axis], value: pointValues[input])
        }
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
    /// (The per-notch display-span lookup this extension used to carry moved into
    /// `ScreenSpanResolver` — a cached rect-containment test instead of a CG query every notch.)

    /// Post a fresh continuous event when a speed gain or axis swap applies.
    fileprivate func postContinuous(_ event: CGEvent, gain: Double, transpose: Bool) {
        Self.continuousScrollEvent(event, gain: gain, transpose: transpose,
                                   lineCarryV: &contLineCarryV, lineCarryH: &contLineCarryH)?
            .post(tap: .cghidEventTap)
    }

    static func continuousScrollEvent(_ event: CGEvent, gain: Double, transpose: Bool,
                                      lineCarryV: inout Double, lineCarryH: inout Double) -> CGEvent? {
        var pV = Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)) * gain
        var pH = Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)) * gain
        // Line/fixedPt outputs are derived from the SAME point-field pixels (sanitized: the tap
        // sees every process's synthetic scroll events, and a huge delta would trap `Int64(_:)`).
        // Reading the input's fixedPt here instead would count 10× too few lines on drivers that
        // follow the CG contract (fixedPt = fractional lines, not pixels).
        var fV = sanitizedDelta(pV)
        var fH = sanitizedDelta(pH)
        if transpose { swap(&pV, &pH); swap(&fV, &fH) }
        guard let out = event.copy() else { return nil }
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
        lineCarryV += fV / lineDiv
        lineCarryH += fH / lineDiv
        let lv = lineCarryV.rounded(.towardZero); lineCarryV -= lv
        let lh = lineCarryH.rounded(.towardZero); lineCarryH -= lh
        out.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: Int64(lv))
        out.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: Int64(lh))
        out.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: fV / lineDiv)
        out.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: fH / lineDiv)
        out.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(int32Clamped(pV)))
        out.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(int32Clamped(pH)))
        out.setIntegerValueField(.eventSourceUserData, value: ScrollAnimator.syntheticTag)
        out.flags = event.flags.subtracting(.maskShift)
        out.timestamp = event.timestamp
        return out
    }

    /// Post a fresh notched wheel event with only direction and optional axes applied.
    static func nativeScrollEvent(_ event: CGEvent, transpose: Bool) -> CGEvent? {
        guard let out = event.copy() else { return nil }
        reverseScrollInPlace(out, vertical: false, horizontal: false, transpose: transpose)
        out.setIntegerValueField(.eventSourceUserData, value: ScrollAnimator.syntheticTag)
        out.flags.remove(.maskShift) // We already applied Shift transposition.
        return out
    }

    fileprivate func postNativeScroll(_ event: CGEvent, transpose: Bool) {
        Self.nativeScrollEvent(event, transpose: transpose)?.post(tap: .cghidEventTap)
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
