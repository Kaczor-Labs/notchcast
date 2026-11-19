// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's paste plain service and transient paste: the route and the wait.

import Foundation

@MainActor
final class PastePlainTextModule: NotchcastModule {
    static let noticeID = "pastePlain"
    /// Covers the palette handing focus back when the command runs from the launcher.
    static let focusDelay: Duration = .milliseconds(80)
    static let staleKeystroke: Duration = .seconds(1)
    /// Up to 1.5 s for the hotkey's keys to come up, then a beat before ⌘V.
    static let releasePoll: Duration = .milliseconds(15)
    static let releasePolls = 100
    static let releaseSettle: Duration = .milliseconds(60)

    private let context: NotchcastContext
    private let system: PastePlainTextSystem
    private var engine: PlainPasteEngine?
    private var keystroke: (any PlainPasteTimer)?
    private var restoreTimer: (any PlainPasteTimer)?
    /// Until `restoreDelay` after this, the target app may still be reading the plain text.
    private var postedAt: ContinuousClock.Instant?

    init(context: NotchcastContext, system: PastePlainTextSystem) {
        self.context = context
        self.system = system
    }

    func start() {
        guard engine == nil else { return }
        engine = PlainPasteEngine(
            board: system.makeBoard(), prepareWrite: { [context] in context.prepareClipboardMutation() },
            didWrite: { [context] in context.synchronizeClipboard(changeCount: $0) })
    }

    func stop() {
        cancelTimers()
        restore()
        engine = nil
        postedAt = nil
    }

    func paste() {
        guard engine != nil else { return }
        context.refreshPermission()
        guard context.isAccessibilityTrusted else {
            return notify(String(localized: "Allow Accessibility access to paste.", table: "NotchcastPastePlainText"))
        }
        cancelTimers()
        let settle = postedAt.map { PlainPasteEngine.restoreDelay - (system.now() - $0) } ?? .zero
        if settle > .zero {
            restoreTimer = system.after(settle) { [weak self] in self?.begin() }
            return
        }
        begin()
    }

    private func begin() {
        restoreTimer = nil
        restore()
        guard let engine else { return }
        let text = engine.text()
        let changeCount = engine.changeCount
        schedule(Self.focusDelay) { $0.deliver(text, expecting: changeCount) }
    }

    /// The app's own matching-style paste first; the lent text only where the app has none.
    private func deliver(_ text: String?, expecting changeCount: Int) {
        guard let engine, engine.changeCount == changeCount else { return }
        guard let text else { return awaitRelease(expecting: changeCount, restores: false) }
        if system.pressMatchStyle() { return }
        switch engine.lend(text) {
        case .refused:
            restore()
            notify(String(localized: "Couldn't read the clipboard, so nothing was pasted.", table: "NotchcastPastePlainText"))
        case .plain(let lent):
            awaitRelease(expecting: lent, restores: true)
        }
    }

    /// ⌘V goes out once the hotkey's keys are up, or anyway after the last poll.
    private func awaitRelease(expecting changeCount: Int, restores: Bool, poll: Int = 0) {
        guard system.modifiersHeld(), poll < Self.releasePolls else {
            return schedule(Self.releaseSettle) { $0.post(expecting: changeCount, restores: restores) }
        }
        schedule(Self.releasePoll) { $0.awaitRelease(expecting: changeCount, restores: restores, poll: poll + 1) }
    }

    private func post(expecting changeCount: Int, restores: Bool) {
        guard let engine else { return }
        guard engine.changeCount == changeCount else { return restore() }
        system.postCommandV()
        guard restores else { return }
        postedAt = system.now()
        restoreTimer = system.after(PlainPasteEngine.restoreDelay) { [weak self] in
            self?.restoreTimer = nil
            self?.restore()
        }
    }

    /// A step stretched past `staleKeystroke` was a sleep, so the app in front may have changed.
    private func schedule(_ delay: Duration, _ work: @escaping @MainActor (PastePlainTextModule) -> Void) {
        let scheduled = system.now()
        keystroke = system.after(delay) { [weak self] in
            guard let self else { return }
            keystroke = nil
            guard system.now() - scheduled < Self.staleKeystroke else { return restore() }
            work(self)
        }
    }

    private func restore() {
        guard let engine else { return }
        for _ in 0..<2 where engine.isRestorePending { engine.restorePending() }
    }

    private func cancelTimers() {
        keystroke?.cancel()
        restoreTimer?.cancel()
        keystroke = nil
        restoreTimer = nil
    }

    private func notify(_ text: String) {
        context.presenter.post(
            IslandNotice(id: Self.noticeID, symbol: "doc.plaintext", text: text, isFailure: true), onTap: nil)
    }
}
