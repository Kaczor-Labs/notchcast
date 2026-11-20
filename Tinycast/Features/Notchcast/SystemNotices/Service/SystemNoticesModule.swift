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

        func symbol(up: Bool) -> String {
            switch self {
            case .wifi: up ? "wifi" : "wifi.slash"
            case .vpn: up ? "lock.shield" : "exclamationmark.shield"
            }
        }

        func text(up: Bool) -> String { self == .wifi ? SystemNoticesPolicy.wifi(up: up) : SystemNoticesPolicy.vpn(up: up) }
    }

    /// One watcher; each but sleep has a checkbox, and an unticked one is not running at all.
    private enum Source: CaseIterable {
        case wifi, vpn, battery, sleep

        var key: String? {
            switch self {
            case .wifi: SystemNoticesPolicy.wifiKey
            case .vpn: SystemNoticesPolicy.vpnKey
            case .battery: SystemNoticesPolicy.batteryKey
            case .sleep: nil
            }
        }

        var link: Link? {
            switch self {
            case .wifi: .wifi
            case .vpn: .vpn
            case .battery, .sleep: nil
            }
        }
    }

    static let batteryNoticeID = "systemNotices.battery"

    private let context: NotchcastContext
    private var links: [Link: LinkWatch] = [:]
    private var battery = BatteryWatch()
    private var watchers: [Source: SystemNoticesWatcher] = [:]
    /// The run each running source started in, so a reading queued by a stopped watcher is dropped.
    private var runs: [Source: Int] = [:]
    private var lastRun = 0
    private var quietUntil = Date.distantPast
    private var checkboxes: NotificationToken?
    private var timer: Task<Void, Never>?
    private(set) var isRunning = false

    init(context: NotchcastContext) { self.context = context }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        battery = BatteryWatch()
        quietUntil = context.now().addingTimeInterval(LinkWatch.wakeQuiet)
        let center = NotificationCenter.default
        checkboxes = NotificationToken(center.addObserver(
            forName: UserDefaults.didChangeNotification, object: context.defaults, queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.sync() }
        }, center: center)
        sync()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        checkboxes = nil
        watchers = [:]
        runs = [:]
        links = [:]
        timer?.cancel()
        timer = nil
        Link.allCases.forEach { context.presenter.end(notice: $0.noticeID) }
        context.presenter.end(notice: Self.batteryNoticeID)
    }

    /// Starts the watcher of each ticked checkbox and stops the rest; the battery keeps its arming meanwhile.
    func sync() {
        guard isRunning else { return }
        for source in Source.allCases {
            let wanted = source.key.map { wants($0) } ?? true
            guard wanted != (runs[source] != nil) else { continue }
            if let link = source.link {
                links[link] = wanted ? LinkWatch() : nil
                links[link]?.quiet(until: quietUntil)
                if !wanted { context.presenter.end(notice: link.noticeID) }
            }
            guard wanted else {
                runs[source] = nil
                watchers[source] = nil
                continue
            }
            lastRun += 1
            runs[source] = lastRun
            watchers[source] = watch(source, run: lastRun)
        }
        evaluate()
    }

    private func watch(_ source: Source, run: Int) -> SystemNoticesWatcher? {
        switch source {
        case .wifi: Self.watchWiFi { [weak self] up in self?.current(.wifi, run)?.observe(.wifi, up: up) }
        case .vpn: Self.watchVPN { [weak self] up in self?.current(.vpn, run)?.observe(.vpn, up: up) }
        case .battery:
            Self.watchBattery { [weak self] in self?.current(.battery, run)?.observeBattery(percent: $0, onAC: $1) }
        case .sleep:
            Self.watchSleep(sleep: { [weak self] in self?.current(.sleep, run)?.sleep() },
                            wake: { [weak self] in self?.current(.sleep, run)?.wake() })
        }
    }

    func observe(_ link: Link, up: Bool) {
        guard isRunning else { return }
        links[link]?.observe(up, at: context.now())
        evaluate()
    }

    func observeBattery(percent: Int, onAC: Bool) {
        guard isRunning, let low = battery.observe(percent: percent, onAC: onAC) else { return }
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
            guard let up = links[link]?.due(at: now) else { continue }
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
        quietUntil = .distantFuture
        for link in Link.allCases { links[link]?.quiet(until: quietUntil) }
        timer?.cancel()
        timer = nil
    }

    private func wake() {
        quietUntil = context.now().addingTimeInterval(LinkWatch.wakeQuiet)
        for link in Link.allCases { links[link]?.quiet(until: quietUntil) }
        evaluate()
    }

    private func current(_ source: Source, _ run: Int) -> SystemNoticesModule? {
        isRunning && runs[source] == run ? self : nil
    }

    /// Each kind has its own checkbox under the switch, on unless the user turned it off.
    private func wants(_ key: String) -> Bool { context.defaults.object(forKey: key) as? Bool ?? true }
}
