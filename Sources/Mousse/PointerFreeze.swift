import CoreGraphics
import Foundation

/// Freeze the mouse pointer in place for the duration of a drag gesture — port of Mac Mouse Fix's
/// `PointerFreeze` (`freezePointer` mode only; the "puppet cursor" variant that keeps a fake cursor
/// following the mouse needs private CGS APIs and is deliberately not ported).
///
/// Mechanism: a dedicated event tap watches mouse-movement/drag events and warps the pointer back
/// to the freeze origin on every one, so the pointer never leaves the origin while the gesture's
/// delta accumulation keeps seeing the full physical movement. The event-source suppression
/// interval is lowered while frozen — the warp would otherwise leave the cursor unresponsive for
/// ~0.25 s after each jump (the pointer "lags behind" the drag) — and restored on unfreeze.
///
/// Threading: `install` runs on the event-tap thread; `freeze`/`unfreeze` are only ever called
/// from that same thread (the drag gesture state is tap-thread-only), and the tap callback fires
/// on that thread's run loop too — so no locking is needed.
final class PointerFreeze {

    static let shared = PointerFreeze()
    private init() {}

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var origin = CGPoint.zero
    private var isFrozen = false
    private var savedSuppression = 0.25

    /// Smallest suppression interval that still lets repeated warps actually hold the pointer
    /// still (a 0 interval makes `CGWarpMouseCursorPosition` stop working entirely). MMF tuning.
    private static let frozenSuppression = 0.07

    /// Create the tap on the engine's tap-thread run loop (idempotent). Must be called from that
    /// thread, before `freeze` can be used. The tap starts disabled — it only does work while frozen.
    func install(on runLoop: CFRunLoop?) {
        guard let runLoop else { return }
        uninstall(from: nil)
        let mask: CGEventMask =
            (1 << CGEventType.mouseMoved.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.rightMouseDragged.rawValue) |
            (1 << CGEventType.otherMouseDragged.rawValue)
        guard let created = CGEvent.tapCreate(tap: .cghidEventTap,
                                              place: .headInsertEventTap,
                                              options: .defaultTap,
                                              eventsOfInterest: mask,
                                              callback: { _, _, event, _ in
                                                  PointerFreeze.shared.warp(event)
                                                  return Unmanaged.passUnretained(event)
                                              },
                                              userInfo: nil) else {
            NSLog("Mousse: pointer-freeze event tap could not be created")
            return
        }
        tap = created
        if let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0) {
            source = src
            CFRunLoopAddSource(runLoop, src, .commonModes)
        }
        CGEvent.tapEnable(tap: created, enable: false)
    }

    /// Explicitly remove and invalidate the event tap and run-loop source.
    func uninstall(from runLoop: CFRunLoop?) {
        if isFrozen {
            unfreeze()
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source, let runLoop {
                CFRunLoopRemoveSource(runLoop, source, .commonModes)
            }
            CFMachPortInvalidate(tap)
            self.tap = nil
            self.source = nil
        }
    }

    /// Reset any active freeze state immediately (e.g. across sleep/wake/device-change).
    func reset() {
        if isFrozen {
            isFrozen = false
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: false)
            }
            CGWarpMouseCursorPosition(origin)
            setSuppression(savedSuppression)
        }
    }

    /// Anchor the pointer at `position` and hold it there until `unfreeze`. Idempotent.
    func freeze(at position: CGPoint) {
        guard !isFrozen, let tap else { return }
        origin = position
        savedSuppression = currentSuppression()
        setSuppression(PointerFreeze.frozenSuppression)
        isFrozen = true
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// Release the pointer. One last warp parks it exactly on the anchor; the suppression interval
    /// is restored so the cursor responds normally again. Idempotent.
    func unfreeze() {
        guard isFrozen, let tap else { return }
        isFrozen = false
        CGEvent.tapEnable(tap: tap, enable: false)
        CGWarpMouseCursorPosition(origin)
        setSuppression(savedSuppression)
    }

    private func warp(_ event: CGEvent) {
        guard isFrozen else { return }
        if event.type == .tapDisabledByTimeout || event.type == .tapDisabledByUserInput {
            // macOS disabled our tap (usually across sleep/wake) — bring it back so the pointer
            // stays frozen for the rest of the drag.
            if let tap, !CGEvent.tapIsEnabled(tap: tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
        }
        CGWarpMouseCursorPosition(origin)
    }

    private func currentSuppression() -> Double {
        let src = CGEventSource(stateID: .combinedSessionState)!
        return src.localEventsSuppressionInterval
    }

    private func setSuppression(_ interval: Double) {
        let src = CGEventSource(stateID: .combinedSessionState)!
        src.localEventsSuppressionInterval = interval
    }
}
