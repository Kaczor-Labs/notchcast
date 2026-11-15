// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's middle click service: rebuilding input on wake and hotplug.

import AppKit
import IOKit

@MainActor
final class MiddleClickModule: NotchcastModule {
    static let switchID = MiddleClickAddon.switches[0].id
    private static let dragRefreshInterval: TimeInterval = 2

    private let context: NotchcastContext
    private let engine = MiddleClickEngine(
        clock: { ProcessInfo.processInfo.systemUptime },
        secondsSinceKeyDown: { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown) },
        post: MiddleClickModule.post)
    private var source: MiddleClickTouchSource?
    private var tapToken: UUID?
    private var dragTimer: Timer?
    private var wakeObserver: NotificationToken?
    private var hotplug: DeviceWatcher?

    init(context: NotchcastContext) { self.context = context }

    func start() {
        guard tapToken == nil else { return }
        let engine = engine
        engine.setDragEnabled(Self.threeFingerDragEnabled())
        dragTimer = Timer.scheduledTimer(withTimeInterval: Self.dragRefreshInterval, repeats: true) { _ in
            engine.setDragEnabled(MiddleClickModule.threeFingerDragEnabled())
        }
        engine.activate()
        startSource()
        let mask = [CGEventType.leftMouseDown, .leftMouseDragged, .leftMouseUp]
            .reduce(CGEventMask(0)) { $0 | NotchcastTapPolicy.mask(for: $1) }
        tapToken = context.subscribe(NotchcastTap(
            switchID: Self.switchID, mask: mask,
            handler: .synchronous { type, event in engine.handle(type, event: event) ? .swallow : .pass },
            reset: { engine.reset() }))
        let center = NSWorkspace.shared.notificationCenter
        // Sleep invalidates the multitouch devices, and the device list is only read at start.
        wakeObserver = NotificationToken(center.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.restartSource() }
        }, center: center)
        hotplug = DeviceWatcher { [weak self] in self?.restartSource() }
    }

    func stop() {
        guard let tapToken else { return }
        engine.deactivate()
        context.unsubscribe(tapToken)
        self.tapToken = nil
        dragTimer?.invalidate()
        dragTimer = nil
        wakeObserver = nil
        hotplug = nil
        source?.stop()
        source = nil
    }

    private func restartSource() {
        guard tapToken != nil else { return }
        engine.reset()
        startSource()
    }

    private func startSource() {
        source?.stop()
        source = MiddleClickTouchSource()
        let engine = engine
        guard source?.start({ device, points, time in engine.frame(device: device, points: points, time: time) })
            == true else { source = nil; return }
    }

    private nonisolated static func threeFingerDragEnabled() -> Bool {
        ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"].contains {
            (CFPreferencesCopyAppValue("TrackpadThreeFingerDrag" as CFString, $0 as CFString) as? NSNumber)?
                .boolValue == true
        }
    }

    // Posted at the HID tap so WindowServer routes it to the window under the pointer.
    private nonisolated static func post(_ type: CGEventType) {
        guard let event = CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: type,
                                  mouseCursorPosition: CGEvent(source: nil)?.location ?? .zero,
                                  mouseButton: .center) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: Paster.tinycastEventTag)
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        event.post(tap: .cghidEventTap)
    }
}

/// Calls back whenever a multitouch device arrives or leaves, so a new trackpad is read at once.
@MainActor
private final class DeviceWatcher {
    private final class MatchRelay: Sendable {
        let fire: @MainActor @Sendable () -> Void
        init(_ fire: @escaping @MainActor @Sendable () -> Void) { self.fire = fire }
    }

    private let relay: MatchRelay
    private var port: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []

    init(_ changed: @escaping @MainActor @Sendable () -> Void) {
        relay = MatchRelay(changed)
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        IONotificationPortSetDispatchQueue(port, .main)
        self.port = port
        let refcon = Unmanaged.passUnretained(relay).toOpaque()
        for kind in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            guard IOServiceAddMatchingNotification(port, kind, IOServiceMatching("AppleMultitouchDevice"),
                                                   Self.callback, refcon, &iterator) == KERN_SUCCESS else { continue }
            Self.drain(iterator)
            iterators.append(iterator)
        }
    }

    isolated deinit {
        iterators.forEach { IOObjectRelease($0) }
        if let port { IONotificationPortDestroy(port) }
    }

    private static let callback: IOServiceMatchingCallback = { refcon, iterator in
        DeviceWatcher.drain(iterator)
        guard let refcon else { return }
        let relay = Unmanaged<MatchRelay>.fromOpaque(refcon).takeUnretainedValue()
        Task { @MainActor in relay.fire() }
    }

    // An iterator left undrained never fires again.
    private nonisolated static func drain(_ iterator: io_iterator_t) {
        while case let entry = IOIteratorNext(iterator), entry != 0 { IOObjectRelease(entry) }
    }
}
