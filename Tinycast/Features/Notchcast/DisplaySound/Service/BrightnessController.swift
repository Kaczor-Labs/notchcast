// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's brightness service: wake settle and DDC retries.

import Foundation
import Observation

/// Refreshes the displays on screen change and wake, and retries silent monitors.
@MainActor @Observable
final class BrightnessController {
    enum StepResult: Sendable, Equatable {
        case applied(BrightnessLevel), unavailable, cancelled
    }

    private(set) var currentDisplays: [BrightnessDisplay] = []

    @ObservationIgnored private let recovery: DisplaySoundRecovery
    @ObservationIgnored private let system: DisplaySoundSystem
    @ObservationIgnored private var running = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var appliedRevision = 0
    @ObservationIgnored private var serial = 0
    @ObservationIgnored private var operations: [UUID: Task<BrightnessDisplayService.Snapshot?, Never>] = [:]
    @ObservationIgnored private var watchers: [AnyObject] = []
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var settlingAfterWake = false
    @ObservationIgnored private var retries: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var extraDimming: Bool?

    init(system: DisplaySoundSystem, recovery: DisplaySoundRecovery? = nil) {
        self.system = system
        self.recovery = recovery ?? DisplaySoundRecovery(system: system)
    }

    isolated deinit {
        refreshTask?.cancel()
        for task in retries.values { task.cancel() }
        for task in operations.values { task.cancel() }
    }

    var isRunning: Bool { running }

    func level(of display: BrightnessDisplay.ID) -> BrightnessLevel? {
        currentDisplays.first(where: { $0.id == display })?.level
    }

    func isAvailable(_ display: BrightnessDisplay.ID) -> Bool {
        recovery.isAvailable(display) && currentDisplays.contains(where: { $0.id == display })
    }

    func start() {
        guard !running else { return }
        running = true
        recovery.activate()
        refreshTask?.cancel()
        watchers = system.watchDisplays { [weak self] woke in self?.scheduleRefresh(woke: woke) }
            + system.watchSleep { [weak self] in self?.relevel(.sleep) }
        refreshTask = Task { [weak self] in await self?.refresh() }
    }

    func stop() {
        guard running else { return }
        running = false
        generation += 1
        watchers = []
        refreshTask?.cancel()
        refreshTask = nil
        settlingAfterWake = false
        for task in retries.values { task.cancel() }
        retries = [:]
        for task in operations.values { task.cancel() }
        operations = [:]
        currentDisplays = []
        extraDimming = nil
        recovery.restore()
    }

    /// Off takes away the dimming below every backlight at once; on lets the keys reach it again.
    func allowExtraDimming(_ on: Bool) {
        guard running, on != extraDimming else { return }
        extraDimming = on
        relevel(.extraDimming(on))
    }

    private func relevel(_ operation: BrightnessDisplayService.Operation) {
        guard running else { return }
        Task { [weak self] in _ = await self?.perform(operation) }
    }

    func refresh() async {
        guard let snapshot = await perform(.refresh(names: system.screenNames())) else { return }
        scheduleRetries(snapshot.retrying)
    }

    @discardableResult
    func set(_ value: Double, for display: BrightnessDisplay.ID) async -> BrightnessLevel? {
        await perform(.set(value, display))?.displays.first(where: { $0.id == display })?.level
    }

    func step(up: Bool, fine: Bool, for display: BrightnessDisplay.ID) async -> StepResult {
        let epoch = generation
        let request = revision + 1
        let result = await perform(.step(up: up, fine: fine, display))
        guard !Task.isCancelled, running, generation == epoch, request >= appliedRevision else { return .cancelled }
        guard let level = result?.displays.first(where: { $0.id == display })?.level else { return .unavailable }
        return .applied(level)
    }

    private func perform(_ operation: BrightnessDisplayService.Operation) async -> BrightnessDisplayService.Snapshot? {
        guard running, !Task.isCancelled else { return nil }
        let token = UUID()
        let epoch = generation
        revision += 1
        let request = revision
        let task = Task { [recovery] in await recovery.perform(operation) }
        operations[token] = task
        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        operations[token] = nil
        guard running, generation == epoch else { return nil }
        if request > appliedRevision, let result {
            appliedRevision = request
            serial = result.serial
            currentDisplays = result.displays
        }
        guard !Task.isCancelled, request >= appliedRevision else { return nil }
        return result
    }

    /// A wake waits out link renegotiation; a screen change during it does not cut it short.
    private func scheduleRefresh(woke: Bool) {
        guard running, woke || !settlingAfterWake else { return }
        refreshTask?.cancel()
        settlingAfterWake = woke
        let delay = woke ? BrightnessRecoveryPolicy.wakeSettle : BrightnessRecoveryPolicy.screenSettle
        refreshTask = Task { [weak self, system] in
            do { try await system.sleep(delay) } catch { return }
            guard let self, !Task.isCancelled else { return }
            settlingAfterWake = false
            await refresh()
        }
    }

    private func scheduleRetries(_ uuids: Set<String>) {
        let epoch = generation
        for uuid in uuids where retries[uuid] == nil {
            retries[uuid] = Task { [weak self, system] in
                for delay in BrightnessRecoveryPolicy.retryDelays {
                    guard let since = self?.serial else { return }
                    do { try await system.sleep(delay) } catch { return }
                    guard let self, generation == epoch else { return }
                    if await perform(.retry(uuid: uuid, since: since)) != nil { break }
                }
                guard let self, generation == epoch else { return }
                retries[uuid] = nil
            }
        }
    }
}
