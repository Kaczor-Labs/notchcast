// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's brightness service: one slider write in flight, latest wins.

import Observation

/// A dragged slider sends one write at a time and then only its latest value, never a backlog.
@MainActor @Observable
final class BrightnessDisplayRowState {
    private(set) var failed = false
    private var pending: Double?
    var display: BrightnessDisplay
    @ObservationIgnored private let controller: BrightnessController
    @ObservationIgnored private var queued: Double?
    @ObservationIgnored private var write: Task<Void, Never>?

    init(display: BrightnessDisplay, controller: BrightnessController) {
        self.display = display
        self.controller = controller
    }

    var value: Double {
        get { pending ?? controller.level(of: display.id)?.value ?? display.level.value }
        set {
            pending = newValue
            queued = newValue
            guard write == nil else { return }
            write = Task { [weak self] in await self?.drain() }
        }
    }

    func update(_ display: BrightnessDisplay) {
        if self.display.level != display.level { failed = false }
        self.display = display
    }

    func cancel() {
        write?.cancel()
        write = nil
        queued = nil
        pending = nil
    }

    private func drain() async {
        while let next = queued, !Task.isCancelled {
            queued = nil
            let result = await controller.set(next, for: display.id)
            guard !Task.isCancelled else { return }
            failed = result == nil
        }
        guard !Task.isCancelled else { return }
        pending = nil
        write = nil
    }
}
