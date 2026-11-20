import Foundation

/// Lists each device as a command and runs one send at a time, reported as one island notice.
@MainActor
final class TaildropModule: NotchcastModule {
    static let noticeID = "taildrop"
    static let symbol = "paperplane"

    private let context: NotchcastContext
    private let system: TaildropSystem
    private(set) var listing: Task<Void, Never>?
    private var sending: Task<Void, Never>?
    private var job: UUID?
    private(set) var isRunning = false

    init(context: NotchcastContext, system: TaildropSystem) {
        self.context = context
        self.system = system
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        context.handleLauncherShown { [weak self] in self?.refresh() }
        refresh()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        listing?.cancel()
        listing = nil
        sending?.cancel()
        settle()
        context.presenter.end(notice: Self.noticeID)
    }

    /// Lists the devices again; `reporting` also says what is wrong, for the command with no device.
    func refresh(reporting: Bool = false) {
        guard isRunning else { return }
        listing?.cancel()
        let system = system
        listing = Task { [weak self] in
            var failure: (any Error)?
            var targets: [TaildropTarget] = []
            do {
                targets = try await TaildropSend.targets(system)
            } catch {
                failure = error
            }
            guard let self, !Task.isCancelled, isRunning else { return }
            listing = nil
            publish(targets, failure: failure as? TaildropFailure)
            guard reporting else { return }
            if let failure {
                post(Self.message(failure), symbol: Self.symbol, failed: true)
            } else {
                post(String(localized: "Taildrop is ready.", table: "NotchcastTaildrop"), symbol: "checkmark")
            }
        }
    }

    func send(to target: TaildropTarget) {
        guard isRunning, sending == nil else { return }
        let (system, job) = (system, UUID())
        self.job = job
        progress(0, of: 1, to: target.name)
        sending = Task { [weak self] in
            let result: Result<Int, any Error>
            do {
                let count = try await TaildropSend.send(to: target.slug, system: system) { [weak self] done, total in
                    guard let self, self.job == job else { return }
                    progress(done, of: total, to: target.name)
                }
                result = .success(count)
            } catch {
                result = .failure(error)
            }
            guard let self, self.job == job else { return }
            settle()
            finish(result)
        }
    }

    func cancel() { sending?.cancel() }

    /// The device list failed without the CLI missing: one command stays, so the reason has a home.
    private func publish(_ targets: [TaildropTarget], failure: TaildropFailure?) {
        guard failure != .notInstalled else { return context.setCommands([]) }
        guard !targets.isEmpty else {
            return context.setCommands([
                command("taildrop", String(localized: "Taildrop", table: "NotchcastTaildrop")) {
                    $0.refresh(reporting: true)
                },
            ])
        }
        context.setCommands(targets.map { target in
            command(target.slug, String(localized: "Taildrop to \(target.name)", table: "NotchcastTaildrop")) {
                $0.send(to: target)
            }
        })
    }

    private func command(
        _ slug: String, _ name: String, run: @escaping @MainActor @Sendable (TaildropModule) -> Void
    ) -> NotchcastCommand {
        NotchcastCommand(
            slug: slug, name: name, symbol: Self.symbol, switchID: TaildropAddon.switchID,
            keywords: ["tailscale", "send", "finder", "file", "folder"],
            run: { context in
                if let module = context.module(TaildropModule.self) { run(module) }
            })
    }

    private func settle() {
        sending = nil
        job = nil
    }

    private func finish(_ result: Result<Int, any Error>) {
        switch result {
        case .success:
            post(String(localized: "Sent", table: "NotchcastTaildrop"), symbol: "checkmark")
        case .failure(is CancellationError):
            post(String(localized: "Cancelled", table: "NotchcastTaildrop"), symbol: Self.symbol)
        case .failure(let error):
            post(Self.message(error), symbol: Self.symbol, failed: true)
            refresh()
        }
    }

    private func progress(_ done: Int, of total: Int, to name: String) {
        let fraction = total > 1 ? Double(done) / Double(total) : nil
        let text = total > 1
            ? String(localized: "Sending \(total) items to \(name)", table: "NotchcastTaildrop")
            : String(localized: "Sending to \(name)", table: "NotchcastTaildrop")
        let notice = IslandNotice(
            id: Self.noticeID, symbol: Self.symbol, text: text, progress: IslandProgress(fraction: fraction))
        context.presenter.post(notice, onTap: { [weak self] in self?.cancel() })
    }

    private func post(_ text: String, symbol: String, failed: Bool = false) {
        let notice = IslandNotice(id: Self.noticeID, symbol: symbol, text: text, isFailure: failed)
        context.presenter.post(notice, onTap: nil)
    }

    static func message(_ error: any Error) -> String {
        (error as? TaildropFailure)?.message ?? TaildropFailure.unknown
    }
}
