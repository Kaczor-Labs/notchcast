// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// watchBattery adapted from Vorssaint faada18's NotchService.startPower: IOKit power-source callbacks.

import AppKit
import IOKit.ps
import Network
import SystemConfiguration

/// Stops its source when the module lets go of it.
final class SystemNoticesWatcher {
    private let cancel: () -> Void

    init(_ cancel: @escaping () -> Void) { self.cancel = cancel }

    deinit { cancel() }
}

extension SystemNoticesModule {
    typealias LinkChanged = @MainActor @Sendable (Bool) -> Void

    /// Up while the Wi-Fi interface has a usable path; off, unjoined or with no address is down.
    static func watchWiFi(_ changed: @escaping LinkChanged) -> SystemNoticesWatcher? {
        let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
        monitor.pathUpdateHandler = { path in
            let up = path.status == .satisfied
            Task { @MainActor in changed(up) }
        }
        monitor.start(queue: DispatchQueue(label: "app.notchcast.system-notices.wifi"))
        return SystemNoticesWatcher { monitor.cancel() }
    }

    /// Tunnel interfaces macOS publishes an IPv4 address for: utun (WireGuard, Tailscale, OpenVPN and most
    /// Network Extension VPNs), ipsec (IKEv2, Cisco IPSec) and ppp (L2TP). Idle system utuns carry none.
    nonisolated static let tunnelPattern = "State:/Network/Interface/(utun|ipsec|ppp)[0-9]+/IPv4"

    /// Up while any tunnel interface holds an address; configd calls back on every change, off the main actor.
    static func watchVPN(_ changed: @escaping LinkChanged) -> SystemNoticesWatcher? {
        let relay = TunnelRelay(changed)
        var context = SCDynamicStoreContext(
            version: 0, info: Unmanaged.passUnretained(relay).toOpaque(), retain: nil, release: nil,
            copyDescription: nil)
        guard let store = SCDynamicStoreCreate(nil, "Notchcast" as CFString, { _, _, info in
            guard let info else { return }
            Unmanaged<TunnelRelay>.fromOpaque(info).takeUnretainedValue().read()
        }, &context) else { return nil }
        let queue = DispatchQueue(label: "app.notchcast.system-notices.vpn")
        guard SCDynamicStoreSetNotificationKeys(store, nil, [tunnelPattern] as CFArray),
              SCDynamicStoreSetDispatchQueue(store, queue) else { return nil }
        queue.async { relay.read() }
        return SystemNoticesWatcher {
            SCDynamicStoreSetDispatchQueue(store, nil)
            withExtendedLifetime(relay) {}
        }
    }

    /// The internal battery's percent and whether it is on AC; nil on a Mac without one, which watches nothing.
    static func watchBattery(_ changed: @escaping @MainActor @Sendable (Int, Bool) -> Void) -> SystemNoticesWatcher? {
        guard readBattery() != nil else { return nil }
        let relay = BatteryRelay(changed)
        guard let source = IOPSNotificationCreateRunLoopSource({ info in
            guard let info else { return }
            Unmanaged<BatteryRelay>.fromOpaque(info).takeUnretainedValue().read()
        }, Unmanaged.passUnretained(relay).toOpaque())?.takeRetainedValue() else { return nil }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        relay.read()
        return SystemNoticesWatcher {
            CFRunLoopSourceInvalidate(source)
            withExtendedLifetime(relay) {}
        }
    }

    static func watchSleep(sleep: @escaping @MainActor @Sendable () -> Void,
                           wake: @escaping @MainActor @Sendable () -> Void) -> SystemNoticesWatcher? {
        let center = NSWorkspace.shared.notificationCenter
        let tokens = [
            NotificationToken(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in sleep() }
            }, center: center),
            NotificationToken(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in wake() }
            }, center: center),
        ]
        return SystemNoticesWatcher { withExtendedLifetime(tokens) {} }
    }

    nonisolated static func readBattery() -> (percent: Int, onAC: Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
                    as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            return (current * 100 / max, description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
        }
        return nil
    }
}

private final class TunnelRelay: Sendable {
    private let changed: SystemNoticesModule.LinkChanged

    init(_ changed: @escaping SystemNoticesModule.LinkChanged) { self.changed = changed }

    func read() {
        let keys = SCDynamicStoreCopyKeyList(nil, SystemNoticesModule.tunnelPattern as CFString) as? [String] ?? []
        let up = !keys.isEmpty
        let changed = changed
        Task { @MainActor in changed(up) }
    }
}

private final class BatteryRelay: Sendable {
    private let changed: @MainActor @Sendable (Int, Bool) -> Void

    init(_ changed: @escaping @MainActor @Sendable (Int, Bool) -> Void) { self.changed = changed }

    func read() {
        guard let reading = SystemNoticesModule.readBattery() else { return }
        let changed = changed
        Task { @MainActor in changed(reading.percent, reading.onAC) }
    }
}
