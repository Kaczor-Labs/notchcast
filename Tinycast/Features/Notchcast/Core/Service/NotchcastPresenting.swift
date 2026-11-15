import Foundation

/// The presentation seam: an add-on says what to show, the core decides where (the island later).
@MainActor
protocol NotchcastPresenting: AnyObject {
    func showLevel(_ level: NotchcastLevel)
    func post(_ notice: NotchcastNotice)
    func end(_ noticeID: UUID)
    func setStatus(_ status: NotchcastStatus?, owner: String)
    func setMenuRows(_ rows: [NotchcastMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void)
}
