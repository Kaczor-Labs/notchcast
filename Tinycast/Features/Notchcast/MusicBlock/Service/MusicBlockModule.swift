// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's music launch blocker: quitting a launch a media key started.

import AppKit

@MainActor
final class MusicBlockModule: NotchcastModule {
    static let switchID = MusicBlockAddon.switches[0].id

    private let context: NotchcastContext
    private var trigger = MusicLaunchTrigger()
    private var tapToken: UUID?
    private var launchObservers: [NotificationToken] = []

    init(context: NotchcastContext) { self.context = context }

    func start() {
        guard tapToken == nil else { return }
        tapToken = context.subscribe(NotchcastTap(
            switchID: Self.switchID, mask: NotchcastTapPolicy.mask(rawType: NotchcastMediaKey.eventType),
            handler: .observe { [weak self] event in self?.noted(event) },
            reset: { [weak self] in self?.trigger.reset() }))
        let center = NSWorkspace.shared.notificationCenter
        // Will-launch usually wins before a window shows; did-launch catches one that slipped past.
        launchObservers = [NSWorkspace.willLaunchApplicationNotification,
                           NSWorkspace.didLaunchApplicationNotification].map { name in
            NotificationToken(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      let bundleID = app.bundleIdentifier else { return }
                let processID = app.processIdentifier
                MainActor.assumeIsolated { self?.launched(bundleID: bundleID, processID: processID) }
            }, center: center)
        }
    }

    func stop() {
        guard let tapToken else { return }
        context.unsubscribe(tapToken)
        self.tapToken = nil
        launchObservers = []
        trigger = MusicLaunchTrigger()
    }

    private func noted(_ event: NotchcastTapEvent) {
        guard let key = event.mediaKey, MusicLaunchPolicy.arms(key) else { return }
        let running = MusicLaunchPolicy.blockedBundleIDs.contains {
            !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty
        }
        guard let keyAt = MusicLaunchPolicy.uptime(eventTimestamp: event.timestamp) else { return }
        trigger.arm(at: keyAt, musicRunning: running)
    }

    private func launched(bundleID: String, processID: pid_t) {
        guard trigger.judge(bundleID: bundleID, processID: processID, now: ProcessInfo.processInfo.systemUptime,
                            gestureAge: Self.secondsSinceGesture(),
                            tapLive: tapIsLive),
              let app = NSRunningApplication(processIdentifier: processID), app.bundleIdentifier == bundleID
        else { return }
        if app.forceTerminate() || app.terminate() { return }
        context.presenter.post(IslandNotice(
            id: "musicBlock.stopFailed", symbol: "exclamationmark.triangle",
            text: String(localized: "Couldn't Stop Apple Music", table: "NotchcastMusicBlock"), isFailure: true),
            onTap: nil)
    }

    /// Without a live tap a missed key looks like no key, so no launch may be blocked.
    private var tapIsLive: Bool { tapToken != nil && context.isAccessibilityTrusted }

    // Modifier keys are left out because holding fn may be how the media key was sent.
    private nonisolated static func secondsSinceGesture() -> TimeInterval {
        [CGEventType.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
         .keyDown].map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min()
            ?? .infinity
    }
}
