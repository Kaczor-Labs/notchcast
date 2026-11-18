import Foundation

@MainActor
final class PastePlainTextModule: NotchcastModule {
    static let noticeID = "pastePlain"
    /// Covers the palette handing focus back when the command runs from the launcher.
    static let focusDelay: Duration = .milliseconds(80)
    /// A focus delay stretched this far was a sleep, so the app in front may have changed.
    static let staleKeystroke: Duration = .seconds(1)

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
        let start = system.now()
        switch engine.paste() {
        case .refused:
            restore()
            notify(String(localized: "Couldn't read the clipboard, so nothing was pasted.", table: "NotchcastPastePlainText"))
        case .passThrough(let changeCount):
            keystroke = system.after(Self.focusDelay) { [weak self] in
                self?.post(expecting: changeCount, since: start, restores: false)
            }
        case .plain(let changeCount):
            keystroke = system.after(Self.focusDelay) { [weak self] in
                self?.post(expecting: changeCount, since: start, restores: true)
            }
        }
    }

    private func post(expecting changeCount: Int, since start: ContinuousClock.Instant, restores: Bool) {
        keystroke = nil
        guard let engine else { return }
        guard engine.changeCount == changeCount, system.now() - start < Self.staleKeystroke else { return restore() }
        system.postCommandV()
        guard restores else { return }
        postedAt = system.now()
        restoreTimer = system.after(PlainPasteEngine.restoreDelay) { [weak self] in
            self?.restoreTimer = nil
            self?.restore()
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
