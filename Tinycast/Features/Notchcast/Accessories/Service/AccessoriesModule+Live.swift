// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint faada18's PeripheralBatterySampler, NotchAccessoryConnectionMonitor and its notifications.

import AppKit
import ApplicationServices
import IOBluetooth
import IOKit
import Synchronization

/// Stops its source when the module lets go of it.
final class AccessoriesWatcher {
    private let cancel: () -> Void

    init(_ cancel: @escaping () -> Void) { self.cancel = cancel }

    deinit { cancel() }
}

extension AccessoriesModule {
    /// Levels the HID services publish in IORegistry: Magic Keyboard, Mouse and Trackpad and most others.
    @concurrent nonisolated static func readHID() async -> [AccessoryBattery] {
        ["AppleDeviceManagementHIDEventService", "IOHIDDevice"].flatMap { className -> [AccessoryBattery] in
            var iterator: io_iterator_t = 0
            guard let matching = IOServiceMatching(className),
                  IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return [] }
            defer { IOObjectRelease(iterator) }
            var devices: [AccessoryBattery] = []
            var service = IOIteratorNext(iterator)
            while service != 0 {
                var properties: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                   let values = properties?.takeRetainedValue() as? [String: Any],
                   let device = AccessoryReadings.hid(values) {
                    devices.append(device)
                }
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            return devices
        }
    }

    /// AirPods-style levels, which only `system_profiler` publishes; empty when it fails or runs past 5 s.
    @concurrent nonisolated static func readProfiler() async -> [AccessoryBattery] {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard let exit = try? process.runObservingExit() else { return [] }
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5, execute: deadline)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        exit.wait()
        deadline.cancel()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else { return [] }
        return AccessoryReadings.profiler(data)
    }

    static func watchConnections(
        _ handler: @escaping @MainActor @Sendable (AccessoryConnectionEvent) -> Void
    ) -> AccessoriesWatcher? {
        let source = AccessoryBluetoothSource(handler)
        AccessoriesThread.shared.perform { source.start() }
        return AccessoriesWatcher { source.cancel() }
    }

    /// The option and an Accessibility grant take effect at once, not at the next poll.
    static func watchBanners(_ defaults: UserDefaults) -> AccessoryBannerHandle? {
        let hider = AccessoryBannerHider(defaults: defaults)
        let thread = AccessoriesThread.shared
        let refresh: @Sendable () -> Void = { thread.perform { hider.refresh() } }
        let local = NotificationCenter.default
        let distributed = DistributedNotificationCenter.default()
        let tokens = [
            NotificationToken(local.addObserver(
                forName: UserDefaults.didChangeNotification, object: defaults, queue: nil) { _ in refresh() },
                center: local),
            NotificationToken(distributed.addObserver(
                forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: nil
            ) { _ in
                refresh()
                // The trust database answers a moment after macOS announces the change.
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) { refresh() }
            }, center: distributed),
        ]
        refresh()
        return AccessoryBannerHandle(
            watcher: AccessoriesWatcher {
                withExtendedLifetime(tokens) {}
                hider.cancel()
            },
            setNames: { names in thread.perform { hider.setNames(names) } },
            refresh: refresh)
    }

    /// Asleep or locked, and back: connections are rebuilt as a silent baseline on the way back.
    static func watchSleep(sleep: @escaping @MainActor @Sendable () -> Void,
                           wake: @escaping @MainActor @Sendable () -> Void) -> AccessoriesWatcher? {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        func observe(_ center: NotificationCenter, _ name: Notification.Name,
                     _ action: @escaping @MainActor @Sendable () -> Void) -> NotificationToken {
            NotificationToken(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in action() }
            }, center: center)
        }
        let tokens = [
            observe(workspace, NSWorkspace.willSleepNotification, sleep),
            observe(workspace, NSWorkspace.didWakeNotification, wake),
            observe(distributed, Notification.Name("com.apple.screenIsLocked"), sleep),
            observe(distributed, Notification.Name("com.apple.screenIsUnlocked"), wake),
        ]
        return AccessoriesWatcher { withExtendedLifetime(tokens) {} }
    }
}

/// IOBluetooth and AX deliver on the run loop they registered on; unchecked: all state sits under `lock`.
final class AccessoriesThread: @unchecked Sendable {
    static let shared = AccessoriesThread()

    private let lock = NSLock()
    private var runLoop: CFRunLoop?
    private var pending: [@Sendable () -> Void] = []
    private var started = false
    private var draining = false

    /// Waits at most `timeout`, so a stuck Accessibility call can delay quitting but never hang it.
    func performAndWait(timeout: TimeInterval, _ work: @escaping @Sendable () -> Void) {
        let done = DispatchSemaphore(value: 0)
        perform {
            work()
            done.signal()
        }
        _ = done.wait(timeout: .now() + timeout)
    }

    func perform(_ work: @escaping @Sendable () -> Void) {
        let action = lock.withLock { () -> (launch: Bool, runLoop: CFRunLoop?) in
            pending.append(work)
            if let runLoop, !draining {
                draining = true
                return (false, runLoop)
            }
            guard !started else { return (false, nil) }
            started = true
            return (true, nil)
        }
        if let runLoop = action.runLoop { scheduleDrain(on: runLoop) }
        guard action.launch else { return }
        let thread = Thread { self.run() }
        thread.name = "Notchcast Accessories"
        thread.qualityOfService = .utility
        thread.start()
    }

    /// Reserved until the running call returns, so a framework's nested run loop never starts the next one.
    private func scheduleDrain(on runLoop: CFRunLoop) {
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) { self.drain() }
        CFRunLoopWakeUp(runLoop)
    }

    private func drain() {
        while let work = lock.withLock({ () -> (@Sendable () -> Void)? in
            guard !pending.isEmpty else {
                draining = false
                return nil
            }
            return pending.removeFirst()
        }) {
            autoreleasepool(invoking: work)
        }
    }

    private func run() {
        let runLoop = CFRunLoopGetCurrent()!
        // The port only keeps the run loop alive between events; nothing polls.
        RunLoop.current.add(NSMachPort(), forMode: .common)
        lock.withLock {
            self.runLoop = runLoop
            draining = true
        }
        scheduleDrain(on: runLoop)
        while true {
            autoreleasepool { _ = CFRunLoopRunInMode(.defaultMode, .greatestFiniteMagnitude, true) }
        }
    }
}

/// Paired devices (dis)connecting, a silent baseline at start; unchecked: confined to `AccessoriesThread`.
private final class AccessoryBluetoothSource: NSObject, @unchecked Sendable {
    private let handler: @MainActor @Sendable (AccessoryConnectionEvent) -> Void
    private let cancelled = Mutex(false)
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnects: [String: IOBluetoothUserNotification] = [:]
    private var connections = AccessoryConnections()

    init(_ handler: @escaping @MainActor @Sendable (AccessoryConnectionEvent) -> Void) { self.handler = handler }

    private var isCancelled: Bool { cancelled.withLock { $0 } }

    func cancel() {
        cancelled.withLock { $0 = true }
        AccessoriesThread.shared.perform { self.unregister() }
    }

    func start() {
        guard !isCancelled else { return }
        var baseline = Set<String>()
        var others: [String] = []
        for device in IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [] {
            guard !isCancelled else { return }
            guard device.isConnected(), let address = device.addressString else { continue }
            baseline.insert(address)
            observeDisconnect(device, address: address)
            if let name = device.name, !AccessoryPolicy.isAccessory(majorClass: UInt32(device.deviceClassMajor)) {
                others.append(name)
            }
        }
        connections.baseline(baseline)
        deliver(.others(names: others))
        let notification = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(connected))
        // A framework call can run a nested run loop and return after `cancel`.
        if isCancelled { notification?.unregister() } else { connectNotification = notification }
    }

    private func unregister() {
        connectNotification?.unregister()
        connectNotification = nil
        disconnects.values.forEach { $0.unregister() }
        disconnects = [:]
    }

    private func observeDisconnect(_ device: IOBluetoothDevice, address: String) {
        guard !isCancelled, disconnects[address] == nil else { return }
        let notification = device.register(forDisconnectNotification: self, selector: #selector(disconnected))
        if isCancelled { notification?.unregister() } else { disconnects[address] = notification }
    }

    @objc private func connected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard !isCancelled, notification === connectNotification, device.isConnected(),
              let address = device.addressString, connections.connect(address) else { return }
        observeDisconnect(device, address: address)
        guard let name = device.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return }
        deliver(.connected(name: name, majorClass: UInt32(device.deviceClassMajor),
                           minorClass: UInt32(device.deviceClassMinor)))
    }

    @objc private func disconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard !isCancelled, !device.isConnected(), let address = device.addressString,
              disconnects[address] === notification else { return }
        connections.disconnect(address)
        disconnects.removeValue(forKey: address)?.unregister()
        guard let name = device.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return }
        deliver(.disconnected(name: name))
    }

    private func deliver(_ event: AccessoryConnectionEvent) {
        let handler = handler
        Task { @MainActor in handler(event) }
    }
}

/// Feeds Notification Center's events to the hider core; unchecked: confined to `AccessoriesThread`.
final class AccessoryBannerHider: @unchecked Sendable {
    private static let notifications = [kAXWindowCreatedNotification, kAXLayoutChangedNotification,
                                        kAXUIElementDestroyedNotification, kAXFocusedWindowChangedNotification]

    private let defaults: UserDefaults
    private let cancelled = Mutex(false)
    private var names: [String: Date] = [:]
    private var observer: AXObserver?
    private var pid: pid_t?
    /// Outlives the observer while a window it moved is not confirmed back.
    private var core: AccessoryBannerHiderCore<AccessoryNativeBannerAccess>?
    private var pass: DispatchWorkItem?

    init(defaults: UserDefaults) { self.defaults = defaults }

    private var enabled: Bool {
        !cancelled.withLock { $0 } && defaults.bool(forKey: AccessoryPolicy.hideBannerKey) && AXIsProcessTrusted()
    }

    /// Puts every window back before it returns, so quitting never leaves a banner off screen.
    func cancel() {
        cancelled.withLock { $0 = true }
        AccessoriesThread.shared.performAndWait(timeout: 2) { self.detach() }
    }

    func setNames(_ names: [String: Date]) {
        self.names = names
        scan()
    }

    /// Attaches to the running Notification Center once allowed; lets go and puts every window back when not.
    func refresh() {
        guard enabled else { return detach() }
        let next = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui")
            .first?.processIdentifier
        guard next != pid || observer == nil else { return scan() }
        detach()
        guard let next else { return }
        var created: AXObserver?
        let callback: AXObserverCallback = { _, element, name, context in
            guard let context else { return }
            let hider = Unmanaged<AccessoryBannerHider>.fromOpaque(context).takeUnretainedValue()
            if name as String == kAXWindowCreatedNotification { hider.prehide(element) } else { hider.scan() }
        }
        guard AXObserverCreate(next, callback, &created) == .success, let created else { return }
        let app = AXUIElementCreateApplication(next)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let added = Self.notifications.filter {
            AXObserverAddNotification(created, app, $0 as CFString, context) == .success
        }
        guard !added.isEmpty else { return }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(created), .commonModes)
        observer = created
        if next != pid || core == nil {
            core = AccessoryBannerHiderCore(access: AccessoryNativeBannerAccess(application: app), now: Date.init)
            pid = next
        }
        scan()
    }

    private func detach() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        scan()
    }

    private func prehide(_ window: AXUIElement) {
        guard enabled, let core else { return }
        core.prehide(window)
        // The banner lays out a few hundredths of a second after its window.
        schedule(Date().addingTimeInterval(0.05))
    }

    /// Judges every window while attached; detached, only puts back what is still away, then lets go.
    func scan() {
        guard let core else { return }
        if observer != nil, enabled { core.scan(names: names) } else { core.restoreAll() }
        if observer == nil, !core.hidesWindows { self.core = nil }
        schedule(core.nextPass)
    }

    private func schedule(_ date: Date?) {
        pass?.cancel()
        pass = nil
        guard let date else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            AccessoriesThread.shared.perform { self.scan() }
        }
        pass = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + max(date.timeIntervalSinceNow, 0.02), execute: work)
    }
}
