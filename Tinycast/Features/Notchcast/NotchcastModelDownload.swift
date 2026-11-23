import Foundation
import Observation

@MainActor
final class NotchcastModelDownload {
    private static let noticeID = "dictation.model.download"
    private let isInstalled: (DictationModel) -> Bool
    private let fetch: (DictationModel) async throws -> Void
    private let fraction: () -> Double?
    private let presenter: any IslandPresenting
    private var download: Task<Void, Error>?

    init(
        isInstalled: @escaping (DictationModel) -> Bool, fetch: @escaping (DictationModel) async throws -> Void,
        fraction: @escaping () -> Double?, presenter: any IslandPresenting
    ) {
        self.isInstalled = isInstalled
        self.fetch = fetch
        self.fraction = fraction
        self.presenter = presenter
    }

    func install(_ model: DictationModel) async throws {
        try Task.checkCancellation()
        guard !isInstalled(model) else { return }
        let task = download ?? start(model)
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
        try Task.checkCancellation()
    }

    private func start(_ model: DictationModel) -> Task<Void, Error> {
        let task = Task {
            let progress = Task { [fraction, presenter] in
                for await fraction in Observations({ fraction() }) {
                    guard !Task.isCancelled else { return }
                    presenter.post(IslandNotice(
                        id: Self.noticeID, symbol: "arrow.down.circle",
                        text: String(localized: "Downloading Parakeet Ultra", table: "Notchcast"),
                        progress: IslandProgress(fraction: fraction)), onTap: nil)
                }
            }
            defer {
                progress.cancel()
                presenter.end(notice: Self.noticeID)
                download = nil
            }
            try await fetch(model)
        }
        download = task
        return task
    }

    func stop() { download?.cancel() }
}
