import Foundation

/// The presentation seam until the island takes it: notices go to the stock HUD, the rest waits.
@MainActor
final class NotchcastHUDPresenter: NotchcastPresenting {
    private weak var core: AppCore?
    private var progressID: UUID?

    init(core: AppCore) { self.core = core }

    func showLevel(_ level: NotchcastLevel) {}

    func post(_ notice: NotchcastNotice) {
        guard let core else { return }
        if notice.isProgress {
            progressID = notice.id
            core.showProgress(notice.title, onCancel: nil)
            return
        }
        let tone: DialogTone = switch notice.tone {
        case .neutral: .neutral
        case .success: .success
        case .danger: .danger
        }
        core.showMessage(notice.title, tone: tone)
    }

    func end(_ noticeID: UUID) {
        guard progressID == noticeID else { return }
        progressID = nil
        core?.hideProgress()
    }

    func setStatus(_ status: NotchcastStatus?, owner: String) {}

    func setMenuRows(_ rows: [NotchcastMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
}
