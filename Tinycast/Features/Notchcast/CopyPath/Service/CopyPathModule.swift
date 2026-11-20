import Foundation

/// The system side of Copy Path, injected so a harness can fake it; `.live` is in `+Live`.
struct CopyPathSystem: Sendable {
    let frontApp: @MainActor @Sendable () -> CopyPathApp?
    let home: String
    let reader: CopyPathReader
    let copy: @MainActor @Sendable (String) -> Bool
    let openSettings: @MainActor @Sendable (CopyPathFailure) -> Void
}

/// One run at a time: a new run cancels the last, and every result is one island notice.
@MainActor
final class CopyPathModule: NotchcastModule {
    static let noticeID = "copyPath"
    static let symbol = "doc.on.clipboard"

    private let context: NotchcastContext
    private let system: CopyPathSystem
    private var runTask: Task<Void, Never>?
    private var operation = UUID()
    private(set) var isRunning = false

    init(context: NotchcastContext, system: CopyPathSystem) {
        self.context = context
        self.system = system
    }

    func start() { isRunning = true }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        cancelRun()
        context.presenter.end(notice: Self.noticeID)
    }

    func run() {
        guard isRunning else { return }
        cancelRun()
        let app = system.frontApp()
        let (home, reader, operation) = (system.home, system.reader, operation)
        runTask = Task { [weak self] in
            let result: Result<CopyPathCopy?, any Error>
            do {
                result = .success(try await CopyPathResolver.resolve(app, home: home, reader: reader))
            } catch {
                result = .failure(error)
            }
            guard let self, !Task.isCancelled, isRunning, self.operation == operation else { return }
            runTask = nil
            finish(result)
        }
    }

    private func cancelRun() {
        runTask?.cancel()
        runTask = nil
        operation = UUID()
    }

    private func finish(_ result: Result<CopyPathCopy?, any Error>) {
        switch result {
        case .success(let copy?):
            context.prepareClipboardMutation()
            guard system.copy(copy.text) else {
                return post(String(localized: "Could not copy to clipboard.", table: "NotchcastCopyPath"), failed: true)
            }
            let count = copy.links
            post(count > 1
                ? String(localized: "Copied \(count) links", table: "NotchcastCopyPath")
                : String(localized: "Copied path", table: "NotchcastCopyPath"), failed: false)
        case .failure(is CancellationError):
            return
        case .failure(let failure as CopyPathFailure):
            post(Self.message(failure), failed: true)
            system.openSettings(failure)
        case .success(nil), .failure:
            post(String(localized: "Unavailable", table: "NotchcastCopyPath"), failed: true)
        }
    }

    private func post(_ text: String, failed: Bool) {
        let symbol = failed ? Self.symbol : "checkmark"
        context.presenter.post(IslandNotice(id: Self.noticeID, symbol: symbol, text: text, isFailure: failed), onTap: nil)
    }

    static func message(_ failure: CopyPathFailure) -> String {
        switch failure {
        case .finderAutomation:
            String(localized: "Allow Automation access to Finder to copy its path.", table: "NotchcastCopyPath")
        case .browserAutomation:
            String(localized: "Allow Automation access to the browser to copy its link.", table: "NotchcastCopyPath")
        case .accessibility:
            String(localized: "Allow Accessibility access to copy the document's path.", table: "NotchcastCopyPath")
        }
    }
}
