// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint faada18's NotchService power path: the low-battery notice on power-source events.

import Foundation

/// Posts an island notice when Wi-Fi or a VPN drops or returns, and once when the Mac's battery runs low.
@MainActor
final class SystemNoticesModule: NotchcastModule {
    enum Link: CaseIterable {
        case wifi, vpn

        var noticeID: String { self == .wifi ? "systemNotices.wifi" : "systemNotices.vpn" }
        var key: String { self == .wifi ? SystemNoticesPolicy.wifiKey : SystemNoticesPolicy.vpnKey }

        func symbol(up: Bool) -> String {
            switch self {
            case .wifi: up ? "wifi" : "wifi.slash"
            case .vpn: up ? "lock.shield" : "exclamationmark.shield"
            }
        }

        func text(up: Bool) -> String { self == .wifi ? SystemNoticesPolicy.wifi(up: up) : SystemNoticesPolicy.vpn(up: up) }
    }

    static let batteryNoticeID = "systemNotices.battery"

    private let context: NotchcastContext
    private var links: [Link: LinkWatch] = [:]
    private var battery = BatteryWatch()
    private var watchers: [SystemNoticesWatcher] = []
    private var timer: Task<Void, Never>?
    /// Bumped per start, so a reading queued by a stopped run's watcher never reaches the next run.
    private var run = 0
    private(set) var isRunning = false

    init(context: NotchcastContext) { self.context = context }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        links = [.wifi: LinkWatch(), .vpn: LinkWatch()]
        battery = BatteryWatch()
        run += 1
        let run = run
        watchers = [
            Self.watchWiFi { [weak self] up in self?.current(run)?.observe(.wifi, up: up) },
            Self.watchVPN { [weak self] up in self?.current(run)?.observe(.vpn, up: up) },
            Self.watchBattery { [weak self] in self?.current(run)?.observeBattery(percent: $0, onAC: $1) },
            Self.watchSleep(sleep: { [weak self] in self?.current(run)?.sleep() },
                            wake: { [weak self] in self?.current(run)?.wake() }),
        ].compactMap(\.self)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        watchers = []
        timer?.cancel()
        timer = nil
        Link.allCases.forEach { context.presenter.end(notice: $0.noticeID) }
        context.presenter.end(notice: Self.batteryNoticeID)
    }

    func observe(_ link: Link, up: Bool) {
        guard isRunning else { return }
        links[link]?.observe(up, at: context.now())
        evaluate()
    }

    func observeBattery(percent: Int, onAC: Bool) {
        guard isRunning, let low = battery.observe(percent: percent, onAC: onAC), wants(SystemNoticesPolicy.batteryKey)
        else { return }
        context.presenter.post(
            IslandNotice(id: Self.batteryNoticeID, symbol: "battery.25percent", text: SystemNoticesPolicy.battery(low),
                         isFailure: true),
            onTap: nil)
    }

    /// Posts every link change that has settled, then waits for the next one that may.
    func evaluate() {
        guard isRunning else { return }
        let now = context.now()
        for link in Link.allCases {
            guard let up = links[link]?.due(at: now), wants(link.key) else { continue }
            context.presenter.post(
                IslandNotice(id: link.noticeID, symbol: link.symbol(up: up), text: link.text(up: up), isFailure: !up),
                onTap: nil)
        }
        schedule(after: now)
    }

    private func schedule(after now: Date) {
        timer?.cancel()
        timer = nil
        guard let next = links.values.compactMap(\.deadline).min() else { return }
        timer = Task { [weak self] in
            guard (try? await Task.sleep(for: .seconds(max(next.timeIntervalSince(now), 0)))) != nil else { return }
            self?.evaluate()
        }
    }

    private func sleep() {
        for link in Link.allCases { links[link]?.quiet(until: .distantFuture) }
        timer?.cancel()
        timer = nil
    }

    private func wake() {
        let until = context.now().addingTimeInterval(LinkWatch.wakeQuiet)
        for link in Link.allCases { links[link]?.quiet(until: until) }
        evaluate()
    }

    private func current(_ run: Int) -> SystemNoticesModule? { isRunning && run == self.run ? self : nil }

    /// Each kind has its own checkbox under the switch, on unless the user turned it off.
    private func wants(_ key: String) -> Bool { context.defaults.object(forKey: key) as? Bool ?? true }
}
