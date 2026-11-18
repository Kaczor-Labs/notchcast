import CoreGraphics
import Foundation

/// One send at a time; the device list is read again each time the launcher opens.
@MainActor
final class TaildropModule: NotchcastModule {
    static let switchID = "taildrop"
    static let noticeID = "taildrop"
    static let symbol = "paperplane"
    /// The last list `tailscale` gave, so the commands are there before it answers again.
    static let targetsKey = "taildropTargets"
    static let escapeKeyCode: Int64 = 53

    private let context: NotchcastContext
    private let environment: TaildropEnvironment
    private var refreshTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?
    private var operation = UUID()
    private var escapeTap: UUID?
    private(set) var isRunning = false

    init(context: NotchcastContext, environment: TaildropEnvironment) {
        self.context = context
        self.environment = environment
    }

    var isSending: Bool { sendTask != nil }
    var isListing: Bool { refreshTask != nil }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        list(TaildropTarget.parse(context.defaults.string(forKey: Self.targetsKey) ?? ""))
        context.handleLauncherOpen { [weak self] in self?.refresh() }
        refresh()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        refreshTask?.cancel()
        refreshTask = nil
        endSend()
        context.presenter.end(notice: Self.noticeID)
    }

    /// A missing CLI hides the commands; one that gives no list keeps the devices it last named.
    func refresh() {
        guard isRunning, refreshTask == nil else { return }
        refreshTask = Task { [weak self, environment] in
            let listing = await TaildropSend.targets(environment)
            guard let self, !Task.isCancelled, isRunning else { return }
            refreshTask = nil
            switch listing {
            case .notInstalled:
                context.defaults.removeObject(forKey: Self.targetsKey)
                list([])
            case .targets(let found):
                context.defaults.set(found.map(\.line).joined(separator: "\n"), forKey: Self.targetsKey)
                list(found)
            case .unavailable:
                break
            }
        }
    }

    func send(to target: TaildropTarget) {
        guard isRunning else { return }
        guard sendTask == nil else {
            let busy = IslandNotice(
                id: Self.noticeID + ".busy", symbol: Self.symbol,
                text: TaildropFailure.busy.errorDescription ?? "", isFailure: true)
            return context.presenter.post(busy, onTap: nil)
        }
        let operation = UUID()
        self.operation = operation
        escapeTap = context.subscribe(
            NotchcastTap(
                switchID: Self.switchID, mask: NotchcastTapPolicy.mask(for: .keyDown),
                handler: .observe { [weak self] event in
                    if event.keyCode == Self.escapeKeyCode { self?.cancel() }
                }))
        let progress: @Sendable (Double?) -> Void = { [weak self] fraction in
            Task { @MainActor [weak self] in self?.show(fraction, target, operation) }
        }
        show(nil, target, operation)
        sendTask = Task { [weak self, environment] in
            let result: Result<Void, any Error>
            do {
                result = .success(try await TaildropSend.send(to: target, environment: environment, progress: progress))
            } catch {
                result = .failure(error)
            }
            guard let self, isRunning, self.operation == operation else { return }
            finish(result, target)
        }
    }

    /// Esc, or a click on the island while it shows the progress.
    func cancel() {
        guard sendTask != nil else { return }
        endSend()
        report(String(localized: "Taildrop cancelled", table: "NotchcastTaildrop"), symbol: "xmark.circle")
    }

    private func list(_ targets: [TaildropTarget]) {
        context.setCommands(targets.map { target in
            NotchcastCommand(
                slug: target.slug, name: String(localized: "Taildrop to \(target.name)", table: "NotchcastTaildrop"),
                symbol: Self.symbol, switchID: Self.switchID, keywords: ["tailscale", "send", "finder"],
                run: { $0.module(TaildropModule.self)?.send(to: target) })
        })
    }

    private func endSend() {
        sendTask?.cancel()
        sendTask = nil
        operation = UUID()
        if let escapeTap { context.unsubscribe(escapeTap) }
        escapeTap = nil
    }

    private func show(_ fraction: Double?, _ target: TaildropTarget, _ operation: UUID) {
        guard self.operation == operation else { return }
        let notice = IslandNotice(
            id: Self.noticeID, symbol: Self.symbol,
            text: String(localized: "Sending to \(target.name)", table: "NotchcastTaildrop"),
            progress: IslandProgress(fraction: fraction))
        context.presenter.post(notice, onTap: { [weak self] in self?.cancel() })
    }

    private func finish(_ result: Result<Void, any Error>, _ target: TaildropTarget) {
        endSend()
        switch result {
        case .success:
            report(String(localized: "Sent to \(target.name)", table: "NotchcastTaildrop"), symbol: "checkmark")
        case .failure(is CancellationError):
            context.presenter.end(notice: Self.noticeID)
        case .failure(let error):
            let failure = error as? TaildropFailure ?? .refused("")
            report(failure.errorDescription ?? "", symbol: Self.symbol, failed: true)
        }
    }

    /// Ended first: a notice that showed progress stays compact on a notch until it is ended.
    private func report(_ text: String, symbol: String, failed: Bool = false) {
        context.presenter.end(notice: Self.noticeID)
        context.presenter.post(IslandNotice(id: Self.noticeID, symbol: symbol, text: text, isFailure: failed), onTap: nil)
    }
}
