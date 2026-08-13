import AppKit
import CoreGraphics
import QuartzCore

/// Resolves which app owns the window under the mouse pointer — the app that will RECEIVE a scroll
/// event (macOS routes scrolling to the window under the cursor, not the focused app), so the
/// scroll-exclusion list must match against this, not the frontmost app.
///
/// Tap-thread only (called from the event-tap callback for scroll events), so no locking: the short
/// result cache and the pid→bundle-ID cache are single-threaded by construction.
final class CursorAppResolver {

    // Window lookup via CGWindowListCopyWindowInfo costs a fraction of a millisecond but scroll
    // ticks arrive at up to display rate — cache the answer. Cursor movement busts the cache via
    // `cacheRadius`, and the engine calls `invalidate()` on the events that change the window
    // under a STATIONARY cursor (Space switch, app activation, wake). That covers the common
    // cases, so the TTL only guards the rare remainder (a window closed/raised under the cursor
    // with no activation change) and can be generous — 0.2 s here meant re-paying the
    // WindowServer lookup 5×/s on the tap thread for the whole length of a long scroll.
    private var cachedBundleID: String?
    private var cachedAt = 0.0
    private var cachedPoint = CGPoint.zero
    private let cacheWindow = 1.0   // s a resolution stays valid absent movement/invalidation
    private let cacheRadius = 16.0  // px the cursor may drift before we re-resolve

    // pid → bundle ID never changes for a live process; NSRunningApplication lookup is the pricey
    // part, so memoize it. Bounded and periodically flushed: without that it accumulates one entry
    // per app ever launched under the cursor, and a RECYCLED pid would keep answering with the
    // exited process's bundle ID — silently applying another app's exclusion/axis-swap rule.
    private var bundleIDByPID: [pid_t: String] = [:]
    private var pidCacheStamp = 0.0
    private let pidCacheLifetime = 300.0 // s — long enough to stay a cache, short enough to self-heal
    private let pidCacheLimit = 64       // hard bound; a flush is cheaper than tracking LRU here

    /// Drop the cached resolution so the next query re-resolves (tap-thread only, like everything
    /// here — the engine relays main-thread notifications via a pending flag it consumes in the
    /// tap callback). The pid→bundle-ID memo stays: pid→ID never changes for a live process.
    func invalidate() {
        cachedAt = 0
    }

    /// Bundle ID of the app owning the topmost normal window containing `point`
    /// (CG global coordinates, as `CGEvent.location` reports). `nil` when nothing matches.
    func bundleID(at point: CGPoint) -> String? {
        // Monotonic clock (like the rest of the codebase): CFAbsoluteTimeGetCurrent is wall time
        // and jumps with NTP/timezone changes, which could hold or bust these caches arbitrarily.
        let now = CACurrentMediaTime()
        if now - cachedAt < cacheWindow,
           abs(point.x - cachedPoint.x) < cacheRadius, abs(point.y - cachedPoint.y) < cacheRadius {
            return cachedBundleID
        }
        cachedBundleID = resolve(at: point)
        cachedAt = now
        cachedPoint = point
        return cachedBundleID
    }

    /// MMF-style lookup for discrete actions. `NSWindow` expects Cocoa coordinates while
    /// `CGEvent.location` uses Quartz coordinates, so flip around the zero screen first. Unlike
    /// enumerating every window, this path still identifies the owner when macOS redacts the
    /// general window list because Screen Recording permission was not granted.
    func navigationBundleID(at quartzPoint: CGPoint) -> String? {
        guard let zeroScreen = NSScreen.screens.first else { return nil }
        let cocoaPoint = NSPoint(x: quartzPoint.x, y: zeroScreen.frame.height - quartzPoint.y)
        let windowNumber = NSWindow.windowNumber(at: cocoaPoint, belowWindowWithWindowNumber: 0)
        guard windowNumber > 0,
              let info = CGWindowListCopyWindowInfo(.optionIncludingWindow,
                                                    CGWindowID(windowNumber)) as? [NSDictionary],
              let pid = info.first?[kCGWindowOwnerPID as String] as? pid_t
        else { return nil }
        return bundleID(for: pid)
    }

    private func resolve(at point: CGPoint) -> String? {
        // Front-to-back on-screen windows; kCGWindowBounds is in the same top-left-origin global
        // space as CGEvent.location, so plain rect containment is the full hit test.
        //
        // Bridged to `[NSDictionary]`, NOT `[[String: Any]]`: the latter deep-converts every key
        // and value of every on-screen window into Swift natives up front, and we read four keys
        // of (usually) one window. Measured on a 31-window desktop: 0.47 ms → 0.22 ms per resolve,
        // on the event-tap thread where every queued mouse event waits behind us.
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [NSDictionary] else { return nil }
        for info in list {
            // Layer 0 = ordinary app windows; skips the menu bar, Dock, and overlay layers, whose
            // huge transparent windows would otherwise shadow the real target.
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.contains(point),
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t
            else { continue }
            return bundleID(for: pid)
        }
        return nil
    }

    private func bundleID(for pid: pid_t) -> String? {
        let now = CACurrentMediaTime()
        if now - pidCacheStamp > pidCacheLifetime || bundleIDByPID.count >= pidCacheLimit {
            bundleIDByPID.removeAll(keepingCapacity: true)
            pidCacheStamp = now
        }
        if let known = bundleIDByPID[pid] { return known }
        guard let id = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { return nil }
        bundleIDByPID[pid] = id
        return id
    }
}
