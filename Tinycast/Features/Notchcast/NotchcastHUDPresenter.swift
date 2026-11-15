import Foundation

/// Stands in for the island until its live states render notices: notices go to the stock HUD.
@MainActor
final class NotchcastHUDPresenter: IslandPresenting {
    private weak var core: AppCore?
    private var progressID: String?

    init(core: AppCore) { self.core = core }

    func showLevel(_ level: IslandLevel) {}

    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) {
        guard let core else { return }
        if notice.progress != nil {
            progressID = notice.id
            core.showProgress(notice.text, onCancel: nil)
            return
        }
        if progressID == notice.id { end(notice: notice.id) }
        core.showMessage(notice.text, tone: notice.isFailure ? .danger : .neutral)
    }

    func end(notice id: String) {
        guard progressID == id else { return }
        progressID = nil
        core?.hideProgress()
    }

    func setStatus(_ status: IslandStatus?, for id: String) {}

    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
}
