import Foundation
import Observation

@MainActor
@Observable
final class CleanerModule: NotchcastModule {
    static let noticeID = "cleaner-result"
    static let offersEmptyTrash = "cleanerOffersEmptyTrash"

    let session: CleanerSession
    let context: NotchcastContext
    private let askToEmptyTrash: @MainActor (String, String, String, String) async -> Bool
    private let emptyTrash: @MainActor () async throws -> Void
    @ObservationIgnored private var reviewID: UUID?
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var cleanTask: Task<Void, Never>?

    private(set) var result: IslandNotice?

    init(
        context: NotchcastContext, session: CleanerSession,
        askToEmptyTrash: @escaping @MainActor (String, String, String, String) async -> Bool,
        emptyTrash: @escaping @MainActor () async throws -> Void
    ) {
        self.context = context
        self.session = session
        self.askToEmptyTrash = askToEmptyTrash
        self.emptyTrash = emptyTrash
    }

    func start() {}

    func stop() {
        if let reviewID { closeReview(reviewID) }
        cleanTask?.cancel()
        context.presenter.end(notice: Self.noticeID)
    }

    func beginReview() -> UUID {
        let id = UUID()
        reviewID = id
        return id
    }

    @discardableResult
    func scan(for id: UUID) -> Task<Void, Never>? {
        guard reviewID == id, cleanTask == nil else { return nil }
        scanTask?.cancel()
        result = nil
        let session = session
        let task = Task { await session.open() }
        scanTask = task
        return task
    }

    func closeReview(_ id: UUID) {
        guard reviewID == id else { return }
        reviewID = nil
        scanTask?.cancel()
        scanTask = nil
    }

    @discardableResult
    func activateReview(visibleItems: [CleanerItem], reveal: () -> Void) -> Task<Void, Never>? {
        guard cleanTask == nil, session.phase == .review, session.selection?.checked.isEmpty == false
        else { return nil }
        guard session.hiddenSelectionCount(among: visibleItems) == 0 else {
            reveal()
            return nil
        }
        let task = Task { [weak self] in
            guard let self else { return }
            defer { self.cleanTask = nil }
            await self.moveSelection()
        }
        cleanTask = task
        return task
    }

    private func moveSelection() async {
        let presenter = context.presenter
        await session.clean(onProgress: { completed, total in
            guard !Task.isCancelled else { return }
            if completed == 0 { self.context.surfaces.dismissLauncher() }
            let fraction = Double(completed) / Double(total)
            let readout = fraction.formatted(.percent.precision(.fractionLength(0)).rounded(rule: .down))
            presenter.post(
                IslandNotice(
                    id: Self.noticeID, symbol: "trash", text: "",
                    progress: IslandProgress(fraction: fraction, headline: false, readout: readout),
                    spokenText: String(localized: "\(completed) of \(total) items processed", table: "NotchcastCleaner")),
                onTap: nil)
        }) { [context] selection in
            let count = selection.checked.count
            let title = count == 1
                ? String(localized: "Move 1 Item to the Trash?", table: "NotchcastCleaner")
                : String(localized: "Move \(count) Items to the Trash?", table: "NotchcastCleaner")
            return await context.confirm?(
                title, String(localized: "You can put them back from the Trash.", table: "NotchcastCleaner"),
                String(localized: "Move to Trash", table: "NotchcastCleaner")) == true
        }

        guard !Task.isCancelled, session.phase == .done, let report = session.report else { return }
        presenter.end(notice: Self.noticeID)
        var notice = Self.notice(for: report)
        result = notice
        if report.movedCount > 0,
            context.defaults.object(forKey: Self.offersEmptyTrash) as? Bool != false,
            await confirmEmptyTrash(), !Task.isCancelled {
            do {
                try await emptyTrash()
                if !notice.isFailure {
                    notice.text = String(localized: "Trash Emptied", table: "NotchcastCleaner")
                }
            } catch {
                notice = IslandNotice(
                    id: Self.noticeID, symbol: "trash",
                    text: String(localized: "Couldn’t Empty the Trash", table: "NotchcastCleaner"), isFailure: true)
            }
        }
        guard !Task.isCancelled else { return }
        result = notice
        presenter.post(notice, onTap: nil)
    }

    private func confirmEmptyTrash() async -> Bool {
        await askToEmptyTrash(
            String(localized: "Empty the Trash?", table: "NotchcastCleaner"),
            String(localized: "This permanently deletes everything in the Trash.", table: "NotchcastCleaner"),
            String(localized: "Empty Trash", table: "NotchcastCleaner"),
            String(localized: "Not Now", table: "NotchcastCleaner"))
    }

    private static func notice(for report: CleanerReport) -> IslandNotice {
        let moved = report.movedCount
        let left = report.entries.count - moved
        if left > 0 || moved == 0 {
            return IslandNotice(
                id: noticeID, symbol: "exclamationmark.triangle",
                text: String(localized: "\(moved) Moved to Trash · \(left) Left in Place", table: "NotchcastCleaner"),
                isFailure: true)
        }
        let size = MeasuredSize(bytes: report.knownMovedBytes).formatted
        return IslandNotice(
            id: noticeID, symbol: "checkmark",
            text: String(localized: "Moved \(size) to the Trash", table: "NotchcastCleaner"))
    }
}
