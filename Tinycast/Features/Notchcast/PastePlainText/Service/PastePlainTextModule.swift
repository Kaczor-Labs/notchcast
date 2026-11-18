import Foundation

@MainActor
final class PastePlainTextModule: NotchcastModule {
    static let noticeID = "pastePlain"

    private let context: NotchcastContext
    private let system: PastePlainTextSystem
    private var engine: PlainPasteEngine?

    init(context: NotchcastContext, system: PastePlainTextSystem) {
        self.context = context
        self.system = system
    }

    func start() {
        guard engine == nil else { return }
        engine = PlainPasteEngine(board: system.makeBoard(), sendPaste: system.sendPaste)
    }

    func stop() {
        engine?.restorePending()
        engine = nil
    }

    func paste() {
        guard let engine else { return }
        context.refreshPermission()
        guard context.isAccessibilityTrusted else {
            let text = String(localized: "Allow Accessibility access to paste.", table: "NotchcastPastePlainText")
            return context.presenter.post(
                IslandNotice(id: Self.noticeID, symbol: "doc.plaintext", text: text, isFailure: true), onTap: nil)
        }
        guard case .plain(let token) = engine.paste() else { return }
        system.after(PlainPasteEngine.restoreDelay) { [weak engine] in engine?.restore(token: token) }
    }
}
