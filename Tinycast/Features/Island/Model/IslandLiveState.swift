import Foundation

/// What the island shows for an update the user started; an automatic offer is `.none`.
struct IslandLiveState: Equatable, Sendable {
    enum Update: Equatable, Sendable {
        case none
        case installing(text: String, progress: Double)
        case ready
        case failed
    }

    static let id = "update"
    static let readySeconds: TimeInterval = 2.4
    static let failureSeconds: TimeInterval = 4
    private(set) var notice: IslandNotice?
    /// How long the notice shows before only the status is left; nil holds it until the stage changes.
    private(set) var noticeSeconds: TimeInterval?
    private(set) var status: IslandStatus?

    init(update: Update) {
        switch update {
        case .none:
            break
        case .installing(let text, let progress):
            notice = IslandNotice(id: Self.id, symbol: "arrow.down.circle", text: text, progress: progress)
        case .ready:
            let text = String(localized: "Update ready")
            notice = IslandNotice(id: Self.id, symbol: "arrow.clockwise.circle", text: text)
            noticeSeconds = Self.readySeconds
            status = IslandStatus(id: Self.id, symbol: "arrow.clockwise.circle", label: text)
        case .failed:
            let text = String(localized: "Update failed")
            notice = IslandNotice(id: Self.id, symbol: "exclamationmark.arrow.circlepath", text: text, isFailure: true)
            noticeSeconds = Self.failureSeconds
            status = IslandStatus(id: Self.id, symbol: "exclamationmark.arrow.circlepath", label: text)
        }
    }
}
