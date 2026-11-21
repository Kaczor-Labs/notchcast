// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's music launch blocker: quitting a launch a media key started.

import AppKit
import CoreServices

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
    private(set) var resuming: Task<Void, Never>?
    private let gestureAge: () -> TimeInterval
    private let isMusicRunning: () -> Bool
    private let processID: (String) -> pid_t?
    private let play: @MainActor (LastPlayer, pid_t) async -> LastPlayer.Outcome
    private let openAutomationSettings: @MainActor () -> Void

    init(context: NotchcastContext, gestureAge: @escaping () -> TimeInterval = MusicBlockModule.secondsSinceGesture,
         isMusicRunning: @escaping () -> Bool = MusicBlockModule.isMusicRunning,
         processID: @escaping (String) -> pid_t? = MusicBlockModule.runningProcessID,
         play: @escaping @MainActor (LastPlayer, pid_t) async -> LastPlayer.Outcome = {
             await MusicBlockModule.sendPlay($0, to: $1)
         },
         openAutomationSettings: @escaping @MainActor () -> Void = MusicBlockModule.openAutomationSettings) {
        self.context = context
        self.gestureAge = gestureAge
        self.isMusicRunning = isMusicRunning
        self.processID = processID
        self.play = play
        self.openAutomationSettings = openAutomationSettings
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
                Task { @MainActor [weak self] in self?.heard(player.announcement, state: state) }
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
              let player = LastPlayer.resume(context.defaults.string(forKey: LastPlayer.storeKey), after: armedKey),
              let pid = processID(player.bundleID)
        else { return }
        resuming?.cancel()
        resuming = Task { [weak self, play] in
            let outcome = await play(player, pid)
            guard outcome != .played, !Task.isCancelled, let self else { return }
            let refused = outcome == .refused
            let text = refused
                ? String(localized: "Allow Automation access for \(player.name).", table: "NotchcastMusicBlock")
                : String(localized: "Couldn't resume \(player.name).", table: "NotchcastMusicBlock")
            context.presenter.post(
                IslandNotice(id: "musicBlock.resumeFailed", symbol: "exclamationmark.triangle", text: text,
                             isFailure: true),
                onTap: refused ? openAutomationSettings : nil)
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

    nonisolated static func runningProcessID(_ bundleID: String) -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier
    }

    static func openAutomationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        else { return }
        NSWorkspace.shared.open(url)
    }

    /// Waits on consent as long as the user takes, then sends to that pid, so a quit player stays quit.
    @concurrent nonisolated static func sendPlay(_ player: LastPlayer, to processID: pid_t)
        async -> LastPlayer.Outcome {
        guard let playEvent = player.playEvent else { return .failed }
        let code = { (text: Substring) in text.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) } }
        let target = NSAppleEventDescriptor(processIdentifier: processID)
        let consent = Int(AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, true))
        guard consent == Int(noErr) else {
            return LastPlayer.outcome(status: consent, refused: NotchcastAppleEvents.refused)
        }
        let event = NSAppleEventDescriptor(
            eventClass: code(playEvent.prefix(4)), eventID: code(playEvent.suffix(4)), targetDescriptor: target,
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        do {
            let reply = try event.sendEvent(options: [.waitForReply, .neverInteract], timeout: 2)
            let status = Int(reply.paramDescriptor(forKeyword: code("errn"))?.int32Value ?? 0)
            return LastPlayer.outcome(status: status, refused: NotchcastAppleEvents.refused)
        } catch {
            return LastPlayer.outcome(status: (error as NSError).code, refused: NotchcastAppleEvents.refused)
        }
    }
}
