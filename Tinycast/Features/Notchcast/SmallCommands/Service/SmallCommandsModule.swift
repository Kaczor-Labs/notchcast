import Foundation

/// One command at a time: a new run cancels the last, and every result is one island notice.
@MainActor
final class SmallCommandsModule: NotchcastModule {
    enum Action: Sendable {
        case password, shorten, noise, airDrop

        var symbol: String {
            switch self {
            case .password: "key"
            case .shorten: "link"
            case .noise: "airpodspro"
            case .airDrop: "airplayaudio"
            }
        }
    }

    static let noticeID = "smallCommands"

    private let context: NotchcastContext
    private let system: SmallCommandsSystem
    private var airDrop: AirDropService?
    private var commandTask: Task<Void, Never>?
    /// Outlives a switch off and on, so the last run's menu cleanup ends before the next one opens it.
    private static var lastNoiseRun: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var operation = UUID()
    private(set) var isRunning = false

    init(context: NotchcastContext, system: SmallCommandsSystem) {
        self.context = context
        self.system = system
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        airDrop = system.makeAirDrop()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        cancelRun()
        airDrop = nil
        noticeTask?.cancel()
        noticeTask = nil
        context.presenter.end(notice: Self.noticeID)
    }

    func run(_ action: Action) {
        guard isRunning else { return }
        cancelRun()
        if action == .password { return show(Result { try copyPassword() }, for: action) }
        let operation = operation
        let previousNoise = action == .noise ? Self.lastNoiseRun : nil
        let task = Task { [weak self] in
            await previousNoise?.value
            let result = await self?.outcome(of: action)
            guard let self, let result, !Task.isCancelled, self.isRunning, self.operation == operation else { return }
            self.commandTask = nil
            self.show(result, for: action)
        }
        commandTask = task
        if action == .noise { Self.lastNoiseRun = task }
    }

    private func cancelRun() {
        commandTask?.cancel()
        commandTask = nil
        airDrop?.stop()
        operation = UUID()
    }

    private func outcome(of action: Action) async -> Result<String, any Error> {
        do {
            switch action {
            case .password: return .success(try copyPassword())
            case .shorten: return .success(try await shortenLink())
            case .noise: return .success(try await switchNoiseControl())
            case .airDrop: return .success(try await shareSelection())
            }
        } catch {
            return .failure(error)
        }
    }

    private func copyPassword() throws -> String {
        let password = try RandomPasswordEngine.make(randomBytes: system.randomBytes)
        guard system.copy(password, true) else { throw SmallCommandsFailure.copyFailed }
        return String(localized: "Password Copied", table: "NotchcastSmallCommands")
    }

    private func shortenLink() async throws -> String {
        var pick = ShortenLinkPolicy.pick(clipboard: system.clipboardText(), browserAddress: nil)
        if pick == nil {
            pick = ShortenLinkPolicy.pick(clipboard: nil, browserAddress: try await system.browserAddress())
        }
        guard let pick, let request = ShortenLinkPolicy.request(for: pick.link) else {
            throw SmallCommandsFailure.noLink
        }
        let reply: (body: Data, status: Int)
        do {
            reply = try await system.fetch(request)
        } catch {
            try Task.checkCancellation()
            throw SmallCommandsFailure.shortenFailed
        }
        try Task.checkCancellation()
        guard let short = ShortenLinkPolicy.shortLink(reply: reply.body, status: reply.status) else {
            throw SmallCommandsFailure.shortenFailed
        }
        guard system.copy(short, false) else { throw SmallCommandsFailure.copyFailed }
        return switch pick.source {
        case .clipboard: String(localized: "Short Link Copied from Clipboard", table: "NotchcastSmallCommands")
        case .browser: String(localized: "Short Link Copied from Browser", table: "NotchcastSmallCommands")
        }
    }

    private func switchNoiseControl() async throws -> String {
        guard let processID = system.controlCenterProcessID() else {
            throw SmallCommandsFailure.controlCenterNotRunning
        }
        let observe = system.observeNoiseControl
        let perform = system.noiseControl
        let service = NoiseControlService(
            observe: { try await observe(processID, $0) },
            perform: { try await perform($0, processID, $1) })
        switch try await service.switchMode() {
        case .switched: return String(localized: "Done", table: "NotchcastSmallCommands")
        case .noAirPods: throw SmallCommandsFailure.noAirPods
        case .unchanged: throw SmallCommandsFailure.noiseControlUnchanged
        case .menuBusy: throw SmallCommandsFailure.controlCenterMenuOpen
        }
    }

    private func shareSelection() async throws -> String {
        guard let airDrop else { throw CancellationError() }
        switch try await airDrop.shareSelection() {
        case .sent: return String(localized: "Done", table: "NotchcastSmallCommands")
        case .cancelled: throw SmallCommandsFailure.airDropCancelled
        case .noSelection: throw SmallCommandsFailure.nothingSelected
        case .unavailable: throw SmallCommandsFailure.airDropUnavailable
        }
    }

    /// The island keeps a notice until its owner ends it, so each result ends itself after a dwell.
    private func show(_ result: Result<String, any Error>, for action: Action) {
        let notice: IslandNotice
        switch result {
        case .success(let text):
            notice = IslandNotice(id: Self.noticeID, symbol: action.symbol, text: text)
        case .failure(is CancellationError):
            return
        case .failure(let error):
            let text = (error as? SmallCommandsFailure)?.errorDescription
                ?? String(localized: "Unavailable", table: "NotchcastSmallCommands")
            notice = IslandNotice(id: Self.noticeID, symbol: action.symbol, text: text, isFailure: true)
        }
        context.presenter.post(notice, onTap: nil)
        noticeTask?.cancel()
        let dwell: Duration = notice.isFailure ? .seconds(4) : .seconds(2.4)
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: dwell)
            guard !Task.isCancelled, let self else { return }
            self.context.presenter.end(notice: Self.noticeID)
        }
    }
}
