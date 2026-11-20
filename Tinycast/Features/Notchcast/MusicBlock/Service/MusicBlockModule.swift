// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's music launch blocker: quitting a launch a media key started.

import AppKit

@MainActor
final class MusicBlockModule: NotchcastModule {
    static let switchID = MusicBlockAddon.switches[0].id
    static let resumeSwitchID = MusicBlockAddon.switches[1].id

    private let context: NotchcastContext
    private var trigger = MusicLaunchTrigger()
    private var tapToken: UUID?
    private var launchObservers: [NotificationCenter.ObservationToken] = []
    private var announcements: [NotificationToken] = []
    private var armedKey: NotchcastMediaKey.Key?
    private var resuming: Task<Void, Never>?
    private let gestureAge: () -> TimeInterval
    private let isMusicRunning: () -> Bool
    private let isRunning: (String) -> Bool
    private let play: @MainActor (LastPlayer) async -> Bool

    init(context: NotchcastContext, gestureAge: @escaping () -> TimeInterval = MusicBlockModule.secondsSinceGesture,
         isMusicRunning: @escaping () -> Bool = MusicBlockModule.isMusicRunning,
         isRunning: @escaping (String) -> Bool = MusicBlockModule.isAppRunning,
         play: @escaping @MainActor (LastPlayer) async -> Bool = { await MusicBlockModule.sendPlay($0) }) {
        self.context = context
        self.gestureAge = gestureAge
        self.isMusicRunning = isMusicRunning
        self.isRunning = isRunning
        self.play = play
    }

    func start() {
        guard tapToken == nil else { return }
        tapToken = context.subscribe(NotchcastTap(
            switchID: Self.switchID, mask: NotchcastTapPolicy.mask(rawType: NotchcastMediaKey.eventType),
            handler: .observe { [weak self] event in self?.noted(event) },
            reset: { [weak self] in self?.trigger.reset() }))
        let workspace = NSWorkspace.shared
        // Will-launch usually wins before a window shows; did-launch catches one that slipped past.
        launchObservers = [
            workspace.notificationCenter.addObserver(of: workspace, for: .willLaunchApplication) { [weak self] in
                self?.launched($0.application)
            },
            workspace.notificationCenter.addObserver(of: workspace, for: .didLaunchApplication) { [weak self] in
                self?.launched($0.application)
            }
        ]
        let distributed = DistributedNotificationCenter.default()
        announcements = LastPlayer.known.map { player in
            NotificationToken(distributed.addObserver(
                forName: Notification.Name(player.announcement), object: nil, queue: .main
            ) { [weak self] note in
                let state = note.userInfo?["Player State"] as? String
                MainActor.assumeIsolated { self?.heard(player.announcement, state: state) }
            }, center: distributed)
        }
    }

    func stop() {
        guard let tapToken else { return }
        context.unsubscribe(tapToken)
        self.tapToken = nil
        launchObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        launchObservers = []
        announcements = []
        resuming?.cancel()
        resuming = nil
        trigger = MusicLaunchTrigger()
    }

    func heard(_ announcement: String, state: String?) {
        guard let player = LastPlayer.playing(announcement: announcement, state: state) else { return }
        context.defaults.set(player.bundleID, forKey: LastPlayer.storeKey)
    }

    private func noted(_ event: NotchcastTapEvent) {
        guard let key = event.mediaKey, MusicLaunchPolicy.arms(key) else { return }
        guard let keyAt = MusicLaunchPolicy.uptime(eventTimestamp: event.timestamp) else { return }
        armedKey = key.key
        trigger.arm(at: keyAt, musicRunning: isMusicRunning())
    }

    func launched(_ app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier,
              trigger.judge(bundleID: bundleID, processID: app.processIdentifier,
                            now: ProcessInfo.processInfo.systemUptime, gestureAge: gestureAge(),
                            tapLive: context.isTapLive)
        else { return }
        if app.forceTerminate() || app.terminate() {
            resumeLastPlayer()
            return
        }
        let text = String(localized: "Couldn't Stop Apple Music Opening", table: "NotchcastMusicBlock")
        context.presenter.post(
            IslandNotice(id: "musicBlock.stopFailed", symbol: "exclamationmark.triangle", text: text, isFailure: true),
            onTap: nil)
    }

    private func resumeLastPlayer() {
        guard context.preferences.isEnabled(Self.resumeSwitchID),
              let player = LastPlayer.resume(context.defaults.string(forKey: LastPlayer.storeKey), after: armedKey,
                                             isRunning: isRunning)
        else { return }
        resuming?.cancel()
        resuming = Task { [weak self, play] in
            guard await !play(player), !Task.isCancelled, let self else { return }
            let text = String(localized: "Couldn't Resume the Last Player", table: "NotchcastMusicBlock")
            context.presenter.post(
                IslandNotice(id: "musicBlock.resumeFailed", symbol: "exclamationmark.triangle", text: text,
                             isFailure: true),
                onTap: nil)
        }
    }

    // Modifier keys are left out because holding fn may be how the media key was sent.
    nonisolated static func secondsSinceGesture() -> TimeInterval {
        [CGEventType.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
         .keyDown].map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min()
            ?? .infinity
    }

    nonisolated static func isMusicRunning() -> Bool {
        MusicLaunchPolicy.blockedBundleIDs.contains {
            !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty
        }
    }

    nonisolated static func isAppRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// The player's own `play` command; a first use asks for Automation consent.
    @concurrent nonisolated static func sendPlay(_ player: LastPlayer) async -> Bool {
        let code = { (text: Substring) in text.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) } }
        let event = NSAppleEventDescriptor(
            eventClass: code(player.playEvent.prefix(4)), eventID: code(player.playEvent.suffix(4)),
            targetDescriptor: NSAppleEventDescriptor(bundleIdentifier: player.bundleID),
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        guard let reply = try? event.sendEvent(options: [.waitForReply, .canInteract], timeout: 5) else { return false }
        return (reply.paramDescriptor(forKeyword: code("errn"))?.int32Value ?? 0) == 0
    }
}
