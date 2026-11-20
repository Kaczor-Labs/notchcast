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

    static func watchBanners(_ defaults: UserDefaults) -> AccessoryBannerHandle? {
        let hider = AccessoryBannerHider(defaults: defaults)
        let thread = AccessoriesThread.shared
        return AccessoryBannerHandle(
            watcher: AccessoriesWatcher { hider.cancel() },
            setNames: { names in thread.perform { hider.setNames(names) } },
            refresh: { thread.perform { hider.refresh() } })
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
        for device in IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [] {
            guard !isCancelled else { return }
            guard device.isConnected(), let address = device.addressString else { continue }
            baseline.insert(address)
            observeDisconnect(device, address: address)
        }
        connections.baseline(baseline)
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

/// Moves the center's banner window off screen while it names our accessory; unchecked: thread-confined.
final class AccessoryBannerHider: @unchecked Sendable {
    /// A new window waits this long, out of sight, for its banner to lay out and for our own event to land.
    static let grace: TimeInterval = 0.6

    private struct Moved {
        let window: AXUIElement
        let origin: CGPoint
        let since: Date
        var kept: Bool
    }

    private let defaults: UserDefaults
    private let cancelled = Mutex(false)
    private var names: [String: Date] = [:]
    private var observer: AXObserver?
    private var pid: pid_t?
    private var app: AXUIElement?
    private var moved: [Moved] = []
    private var budget = 0

    init(defaults: UserDefaults) { self.defaults = defaults }

    private var enabled: Bool {
        !cancelled.withLock { $0 } && defaults.bool(forKey: AccessoryPolicy.hideBannerKey) && AXIsProcessTrusted()
    }

    func cancel() {
        cancelled.withLock { $0 = true }
        AccessoriesThread.shared.perform { self.detach() }
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
        guard next != pid || observer == nil else { return }
        detach()
        guard let next else { return }
        var created: AXObserver?
        let callback: AXObserverCallback = { _, element, name, context in
            guard let context else { return }
            let hider = Unmanaged<AccessoryBannerHider>.fromOpaque(context).takeUnretainedValue()
            if name as String == kAXWindowCreatedNotification { hider.prehide(element) }
            hider.scan()
        }
        guard AXObserverCreate(next, callback, &created) == .success, let created else { return }
        let app = AXUIElementCreateApplication(next)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let added = [kAXWindowCreatedNotification, kAXLayoutChangedNotification].filter {
            AXObserverAddNotification(created, app, $0 as CFString, context) == .success
        }
        guard !added.isEmpty else { return }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(created), .commonModes)
        observer = created
        self.app = app
        pid = next
    }

    private func restore() {
        for record in moved { _ = move(record.window, to: record.origin) }
        moved = []
    }

    private func detach() {
        restore()
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        app = nil
        pid = nil
    }

    /// A window the center just made goes out of sight before its banner draws; `scan` decides if it stays.
    private func prehide(_ window: AXUIElement) {
        guard enabled, !centerIsOpen(), hide(window, kept: false) else { return }
        for delay in [0.05, Self.grace] {
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                AccessoriesThread.shared.perform { self.scan() }
            }
        }
    }

    /// Keeps out of sight each window whose transient banners all name our accessories, and puts back the rest.
    func scan() {
        guard observer != nil else { return }
        guard enabled, let app else { return detach() }
        guard !centerIsOpen() else { return restore() }
        budget = 400
        let now = Date()
        let live = names.filter { $0.value > now }
        var seen: [AXUIElement] = []
        for window in elements(app, kAXWindowsAttribute) {
            seen.append(window)
            var banners: [(texts: [String], transient: Bool)] = []
            findBanners(window, depth: 0, into: &banners)
            let ours = !banners.isEmpty && banners.allSatisfy {
                $0.transient && AccessoryPolicy.hides(banner: $0.texts, names: live, now: now)
            }
            let index = moved.firstIndex { CFEqual($0.window, window) }
            if ours {
                if let index { moved[index].kept = true } else { _ = hide(window, kept: true) }
            } else if let index, moved[index].kept || now.timeIntervalSince(moved[index].since) >= Self.grace {
                _ = move(window, to: moved[index].origin)
                moved.remove(at: index)
            }
        }
        moved.removeAll { record in !seen.contains { CFEqual($0, record.window) } }
    }

    private func hide(_ window: AXUIElement, kept: Bool) -> Bool {
        let screens = displays()
        guard !screens.isNull, let frame = frame(window), frame.intersects(screens) else { return false }
        let away = CGPoint(x: screens.minX - frame.width - 1_000, y: screens.minY - frame.height - 1_000)
        guard move(window, to: away) else { return false }
        guard let landed = self.frame(window), !landed.intersects(screens) else {
            _ = move(window, to: frame.origin)
            return false
        }
        moved.removeAll { CFEqual($0.window, window) }
        moved.append(Moved(window: window, origin: frame.origin, since: Date(), kept: kept))
        return true
    }

    /// The open center keeps its banners in the same window as its list, which is never ours to move.
    private func centerIsOpen() -> Bool {
        guard let app else { return false }
        return value(app, kAXFocusedWindowAttribute) != nil
    }

    private func findBanners(_ node: AXUIElement, depth: Int, into banners: inout [(texts: [String], transient: Bool)]) {
        guard depth <= 10, budget > 0 else { return }
        budget -= 1
        let subrole = value(node, kAXSubroleAttribute) as? String ?? ""
        if subrole.hasPrefix("AXNotificationCenterBanner") || subrole.hasPrefix("AXNotificationCenterAlert") {
            var texts: [String] = []
            collectTexts(node, depth: depth, into: &texts)
            banners.append((texts, subrole.hasPrefix("AXNotificationCenterBanner")))
            return
        }
        for child in elements(node, kAXChildrenAttribute) { findBanners(child, depth: depth + 1, into: &banners) }
    }

    private func collectTexts(_ node: AXUIElement, depth: Int, into texts: inout [String]) {
        guard depth <= 14, budget > 0 else { return }
        budget -= 1
        for attribute in [kAXValueAttribute, kAXDescriptionAttribute, kAXTitleAttribute] {
            if let text = value(node, attribute) as? String, !text.isEmpty { texts.append(text) }
        }
        for child in elements(node, kAXChildrenAttribute) { collectTexts(child, depth: depth + 1, into: &texts) }
    }

    private func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(element, 0.1)
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success ? result : nil
    }

    private func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        (value(element, attribute) as? [AXUIElement]).map { Array($0.prefix(64)) } ?? []
    }

    /// Global coordinates, top-left origin: the space both AX positions and display bounds use.
    private func frame(_ window: AXUIElement) -> CGRect? {
        guard let position = value(window, kAXPositionAttribute), let size = value(window, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &origin),
              AXValueGetValue(unsafeDowncast(size, to: AXValue.self), .cgSize, &extent) else { return nil }
        return CGRect(origin: origin, size: extent)
    }

    private func move(_ window: AXUIElement, to origin: CGPoint) -> Bool {
        var origin = origin
        guard let value = AXValueCreate(.cgPoint, &origin) else { return false }
        AXUIElementSetMessagingTimeout(window, 0.1)
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value) == .success
    }

    private func displays() -> CGRect {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return .null }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return .null }
        return ids.prefix(Int(count)).map(CGDisplayBounds).reduce(CGRect.null) { $0.union($1) }
    }
}
