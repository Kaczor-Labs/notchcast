// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint faada18's NotchAccessoryService: connect and low-battery notices from one sampler.

import Foundation

/// What the Bluetooth watcher reports: values only, so no device object reaches the main actor.
enum AccessoryConnectionEvent: Equatable, Sendable {
    case connected(name: String, majorClass: UInt32, minorClass: UInt32)
    case disconnected(name: String)
    /// Computers, phones and access points connected when the watcher started.
    case others(names: [String])
}

/// The Accessibility watcher over Notification Center's banners, and the names it may hide them for.
struct AccessoryBannerHandle {
    let watcher: AccessoriesWatcher
    /// Lowercased accessory names, each until the moment it stops counting.
    let setNames: @Sendable ([String: Date]) -> Void
    /// Attaches once Accessibility is granted and the option is on, and lets go when either is not.
    let refresh: @Sendable () -> Void
}

/// Posts a notice when a Bluetooth accessory connects or runs low, and keeps the Accessories page current.
@MainActor
final class AccessoriesModule: NotchcastModule {
    /// IORegistry levels are cheap to read; the 20% warning needs a reading at least this often.
    nonisolated static let poll: Duration = .seconds(15)
    /// `system_profiler` costs a process, so AirPods-style levels refresh this rarely unless asked.
    nonisolated static let profilerAge: TimeInterval = 300
    /// A new connection's levels reach `system_profiler` a moment after the connection itself.
    nonisolated static let afterConnect: Duration = .seconds(4)

    private let context: NotchcastContext
    private let sleep: @Sendable (Duration) async throws -> Void
    private var low = AccessoryLowWatch()
    private var announced: [String: Date] = [:]
    /// Connected devices that are not accessories, kept off the page by name.
    private var others: Set<String> = []
    private var quietUntil = Date.distantPast
    private var hid: [AccessoryBattery] = []
    private var profiled: [AccessoryBattery] = []
    private var profiledAt = Date.distantPast
    private var gone: [String: Date] = [:]
    private(set) var devices: [AccessoryBattery] = []
    private var posted: Set<String> = []
    private var page: IslandPage?
    private var connections: AccessoriesWatcher?
    private var sleepWatcher: AccessoriesWatcher?
    private var banners: AccessoryBannerHandle?
    private var loop: Task<Void, Never>?
    private var reads: [UUID: Task<Void, Never>] = [:]
    /// Bumped per start, so a reading queued by a stopped run never reaches the next one.
    private var run = 0
    private(set) var isRunning = false

    init(context: NotchcastContext,
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.context = context
        self.sleep = sleep
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        run += 1
        let run = run
        connect(run)
        sleepWatcher = Self.watchSleep(sleep: { [weak self] in self?.current(run)?.suspend() },
                                       wake: { [weak self] in self?.current(run)?.resume() })
        banners = Self.watchBanners(context.defaults)
        let sleep = sleep
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let module = self?.current(run) else { return }
                module.banners?.refresh()
                await module.read(profilerAge: Self.profilerAge)
                do { try await sleep(Self.poll) } catch { return }
            }
        }
        context.presenter.watchPages(id: AccessoryPage.id) { [weak self] visible in
            guard visible else { return }
            self?.current(run)?.spawn(profilerAge: 60)
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        context.presenter.watchPages(id: AccessoryPage.id, onChange: nil)
        loop?.cancel()
        loop = nil
        reads.values.forEach { $0.cancel() }
        reads = [:]
        connections = nil
        sleepWatcher = nil
        banners = nil
        posted.forEach { context.presenter.end(notice: $0) }
        posted = []
        context.presenter.setPage(nil, id: AccessoryPage.id, onAction: nil)
        page = nil
        low = AccessoryLowWatch()
        announced = [:]
        others = []
        quietUntil = .distantPast
        hid = []
        profiled = []
        profiledAt = .distantPast
        gone = [:]
        devices = []
    }

    /// Reads IORegistry levels, and `system_profiler`'s once its last reading is older than `profilerAge`.
    func read(profilerAge: TimeInterval) async {
        guard isRunning else { return }
        let run = run
        let started = context.now()
        let profiles = started.timeIntervalSince(profiledAt) >= profilerAge
        if profiles { profiledAt = started }
        let hid = await Self.readHID()
        let profiled = profiles ? await Self.readProfiler() : nil
        guard current(run) != nil, !Task.isCancelled else { return }
        self.hid = hid.filter { (gone[$0.key] ?? .distantPast) < started }
        if let profiled {
            self.profiled = profiled.filter { (gone[$0.key] ?? .distantPast) < started }
        }
        apply()
    }

    func handle(_ event: AccessoryConnectionEvent) {
        guard isRunning else { return }
        switch event {
        case let .connected(name, major, minor):
            guard AccessoryPolicy.isAccessory(majorClass: major) else {
                others.insert(AccessoryReadings.key(name))
                return apply()
            }
            gone[AccessoryReadings.key(name)] = nil
            guard AccessoryPolicy.announcesConnection(name: name, majorClass: major) else { return }
            if wants(AccessoryPolicy.connectKey), context.now() >= quietUntil {
                announced[AccessoryReadings.key(name)] = context.now().addingTimeInterval(AccessoryPolicy.bannerWindow)
                post("accessories.connected.\(AccessoryReadings.key(name))",
                     symbol: AccessoryReadings.symbol(name: name, majorClass: major, minorClass: minor),
                     text: AccessoryPolicy.connected(name), failure: false)
                pushBannerNames()
            }
            spawn(after: Self.afterConnect, profilerAge: 0)
        case let .disconnected(name):
            let key = AccessoryReadings.key(name)
            gone[key] = context.now()
            others.remove(key)
            low.forget(name)
            hid.removeAll { $0.key == key }
            profiled.removeAll { $0.key == key }
            for id in ["accessories.connected.\(key)", "accessories.low.\(key)"] where posted.remove(id) != nil {
                context.presenter.end(notice: id)
            }
            apply()
        case let .others(names):
            others = Set(names.map(AccessoryReadings.key))
            apply()
        }
    }

    /// Asleep or locked: connections stop, and after it they start again from a silent baseline.
    private func suspend() {
        quietUntil = .distantFuture
        connections = nil
    }

    private func resume() {
        quietUntil = context.now().addingTimeInterval(AccessoryPolicy.wakeQuiet)
        connect(run)
    }

    private func connect(_ run: Int) {
        connections = nil
        connections = Self.watchConnections { [weak self] in self?.current(run)?.handle($0) }
    }

    private func apply() {
        devices = AccessoryReadings.merge(hid: hid, profiler: profiled).filter { !others.contains($0.key) }
        for device in low.consume(devices) where wants(AccessoryPolicy.lowKey) {
            announced[device.key] = context.now().addingTimeInterval(AccessoryPolicy.bannerWindow)
            post("accessories.low.\(device.key)", symbol: AccessoryReadings.symbol(device.kind, name: device.name),
                 text: AccessoryPolicy.low(device.name, percent: device.percent), failure: true)
        }
        pushBannerNames()
        let next = AccessoryPage.page(devices)
        guard next != page else { return }
        page = next
        context.presenter.setPage(next, id: AccessoryPage.id) { [weak self] action in
            guard action == IslandPage.refreshAction, let self, self.isRunning else { return }
            self.spawn(profilerAge: 0)
        }
    }

    /// An extra read outside the poll, owned until it ends and cancelled by `stop`.
    private func spawn(after delay: Duration? = nil, profilerAge: TimeInterval) {
        let id = UUID()
        let run = run
        let sleep = sleep
        reads[id] = Task { [weak self] in
            if let delay { guard (try? await sleep(delay)) != nil else { return } }
            await self?.current(run)?.read(profilerAge: profilerAge)
            self?.reads[id] = nil
        }
    }

    private func post(_ id: String, symbol: String, text: String, failure: Bool) {
        posted.insert(id)
        context.presenter.post(IslandNotice(id: id, symbol: symbol, text: text, isFailure: failure)) { [weak self] in
            self?.context.presenter.showPage(id: AccessoryPage.id)
        }
    }

    /// Our own notices of the last seconds: macOS's banners for them are duplicates.
    private func pushBannerNames() {
        guard let banners else { return }
        let now = context.now()
        announced = announced.filter { $0.value > now }
        banners.setNames(announced)
    }

    private func current(_ run: Int) -> AccessoriesModule? { isRunning && run == self.run ? self : nil }

    /// Each notice kind has its own checkbox under the switch, on unless the user turned it off.
    private func wants(_ key: String) -> Bool { context.defaults.object(forKey: key) as? Bool ?? true }
}
