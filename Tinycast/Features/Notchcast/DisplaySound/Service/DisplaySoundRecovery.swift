// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's brightness service: wake settle and DDC retries.

import Foundation

@MainActor
final class DisplaySoundRecovery: NotchcastModule {
    private let service: BrightnessDisplayService
    private let system: DisplaySoundSystem
    private var tail: Task<BrightnessDisplayService.Snapshot?, Never>?
    private var watchers: [AnyObject] = []
    private var settling: Task<Void, Never>?
    private var generation = 0
    private var running = true

    init(system: DisplaySoundSystem) {
        self.system = system
        service = BrightnessDisplayService(displays: system.displays)
    }

    isolated deinit { settling?.cancel() }

    func start() { running = true }

    /// Quit: the process may exit as soon as this returns, so the restore cannot wait for a task.
    func stop() {
        running = false
        activate()
        service.restoreBeforeExit(within: BrightnessRecoveryPolicy.quitWait)
    }

    func activate() {
        generation += 1
        settling?.cancel()
        settling = nil
        watchers = []
    }

    func isAvailable(_ id: BrightnessDisplay.ID) -> Bool { service.isAvailable(id) }

    func perform(_ operation: BrightnessDisplayService.Operation) async -> BrightnessDisplayService.Snapshot? {
        let predecessor = tail
        let task = Task { [service] in
            _ = await predecessor?.value
            guard !Task.isCancelled else { return nil as BrightnessDisplayService.Snapshot? }
            return await service.perform(operation)
        }
        tail = task
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func restore() {
        activate()
        let epoch = generation
        let predecessor = tail
        tail = Task { [weak self, service] in
            _ = await predecessor?.value
            let restored = await service.restoreAll()
            guard let self, generation == epoch, running, !restored else { return nil }
            watchers = system.watchDisplays { [weak self] woke in self?.schedule(woke: woke) }
            return nil
        }
    }

    private func schedule(woke: Bool) {
        settling?.cancel()
        let epoch = generation
        let delay = woke ? BrightnessRecoveryPolicy.wakeSettle : BrightnessRecoveryPolicy.screenSettle
        settling = Task { [weak self, system] in
            do { try await system.sleep(delay) } catch { return }
            guard let self, running, generation == epoch, !Task.isCancelled else { return }
            restore()
        }
    }
}
