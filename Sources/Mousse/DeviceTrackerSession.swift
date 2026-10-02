import Foundation
import IOKit.hid
import os

/// One run of `DeviceTracker`'s HID watcher: owns its thread, run loop, manager and device table.
final class DeviceTrackerSession: DeviceTrackingSession {
    private weak var tracker: DeviceTracker?
    private let identity: UUID
    private let lock = OSAllocatedUnfairLock()
    private var runLoop: CFRunLoop? // guarded by `lock`
    private var started = false
    private var stopped = false     // guarded by `lock`

    // Session thread only.
    private var registry = HIDDeviceRegistry()

    init(tracker: DeviceTracker, identity: UUID) { self.tracker = tracker; self.identity = identity }

    func start() {
        lock.lock()
        guard !started, !stopped else { lock.unlock(); return }
        started = true
        lock.unlock()
        let t = Thread { [self] in run() } // the thread retains the session until it exits
        t.name = "com.mousse.device-tracker"
        t.qualityOfService = .userInteractive
        t.start()
    }

    /// Ends the run loop; the session thread then closes the manager and exits. Any thread.
    func stop() {
        lock.lock()
        stopped = true
        let rl = runLoop
        lock.unlock()
        guard let rl else { return } // not running yet: `run()` sees `stopped` and bails out
        // A queued block, not a bare CFRunLoopStop: the latter is lost if the thread hasn't
        // entered CFRunLoopRun yet, while the block waits for it.
        CFRunLoopPerformBlock(rl, CFRunLoopMode.defaultMode.rawValue) { CFRunLoopStop(CFRunLoopGetCurrent()) }
        CFRunLoopWakeUp(rl)
    }

    private func run() {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let devices: [[String: Any]] = [
            [kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
             kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Mouse],
            [kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
             kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Pointer],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(mgr, devices as CFArray)
        // Only the scroll elements: pointer motion would wake this thread at the full report
        // rate for nothing (profiles are scroll-only).
        let values: [[String: Any]] = [
            [kIOHIDElementUsagePageKey as String: kHIDPage_GenericDesktop,
             kIOHIDElementUsageKey as String: kHIDUsage_GD_Wheel],
            [kIOHIDElementUsagePageKey as String: kHIDPage_Consumer,
             kIOHIDElementUsageKey as String: kHIDUsage_Csmr_ACPan],
        ]
        IOHIDManagerSetInputValueMatchingMultiple(mgr, values as CFArray)

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, { context, _, _, device in
            guard let context else { return }
            Unmanaged<DeviceTrackerSession>.fromOpaque(context).takeUnretainedValue().deviceAdded(device)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, { context, _, _, device in
            guard let context else { return }
            Unmanaged<DeviceTrackerSession>.fromOpaque(context).takeUnretainedValue().deviceRemoved(device)
        }, ctx)
        IOHIDManagerRegisterInputValueCallback(mgr, { context, _, _, value in
            guard let context else { return }
            Unmanaged<DeviceTrackerSession>.fromOpaque(context).takeUnretainedValue().inputValue(value)
        }, ctx)

        let rl = CFRunLoopGetCurrent()!
        lock.lock()
        if stopped { lock.unlock(); return }
        runLoop = rl
        lock.unlock()

        IOHIDManagerScheduleWithRunLoop(mgr, rl, CFRunLoopMode.defaultMode.rawValue)
        defer {
            IOHIDManagerUnscheduleFromRunLoop(mgr, rl, CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
            lock.lock(); runLoop = nil; lock.unlock()
        }
        let opened = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        guard opened == kIOReturnSuccess else {
            NSLog("Mousse: device tracker IOHIDManagerOpen failed (0x%X); will retry while needed", opened)
            DispatchQueue.main.async { [weak tracker, identity] in tracker?.sessionOpenFailed(from: identity) }
            return
        }
        // Keep the loop alive without devices; invalidate the port on every session exit.
        let keepAlive = NSMachPort()
        RunLoop.current.add(keepAlive, forMode: .default)
        defer { keepAlive.invalidate() }
        CFRunLoopRun()
    }

    private func info(for device: IOHIDDevice) -> HIDDeviceInfo {
        let ptr = UInt(bitPattern: Unmanaged.passUnretained(device).toOpaque())
        if let known = registry.devices[ptr] { return known }
        func intProp(_ key: String) -> Int {
            (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0
        }
        let vendor = intProp(kIOHIDVendorIDKey)
        let product = intProp(kIOHIDProductIDKey)
        let name = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String)
            .flatMap { $0.isEmpty ? nil : $0 } ?? "Mouse \(HIDDeviceInfo.key(vendorID: vendor, productID: product))"
        let info = HIDDeviceInfo(key: HIDDeviceInfo.key(vendorID: vendor, productID: product), name: name)
        registry.add(info, interface: ptr)
        return info
    }

    private func deviceAdded(_ device: IOHIDDevice) {
        _ = info(for: device)
        publish()
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        let ptr = UInt(bitPattern: Unmanaged.passUnretained(device).toOpaque())
        if let gone = registry.remove(interface: ptr) { tracker?.deviceGone(gone, from: identity) }
        publish()
    }

    private func inputValue(_ value: IOHIDValue) {
        guard IOHIDValueGetIntegerValue(value) != 0 else { return } // idle reports carry 0
        let device = IOHIDElementGetDevice(IOHIDValueGetElement(value))
        tracker?.setActiveKey(info(for: device).key, from: identity)
    }

    private func publish() {
        let list = registry.connected
        DispatchQueue.main.async { [weak tracker, identity] in tracker?.publish(list, from: identity) }
    }
}


/// Multiple HID interfaces of one model must not appear as duplicate mice or clear each other.
struct HIDDeviceRegistry {
    private(set) var devices: [UInt: HIDDeviceInfo] = [:]
    mutating func add(_ info: HIDDeviceInfo, interface: UInt) { devices[interface] = info }
    mutating func remove(interface: UInt) -> String? {
        guard let gone = devices.removeValue(forKey: interface),
              !devices.values.contains(where: { $0.key == gone.key }) else { return nil }
        return gone.key
    }
    var connected: [HIDDeviceInfo] {
        var seen = Set<String>()
        return devices.sorted(by: { $0.key < $1.key }).map(\.value)
            .filter { seen.insert($0.key).inserted }
            .sorted { ($0.name, $0.key) < ($1.name, $1.key) }
    }
}
