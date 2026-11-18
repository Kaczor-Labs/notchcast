import Foundation

/// Lists only the commands the connected headset offers and runs one switch at a time.
@MainActor
final class NoiseControlModule: NotchcastModule {
    static let noticeID = "noiseControl"
    /// Outlives a stopped module: a walk ignores cancellation, so a restarted one must wait it out.
    private(set) static var isWalking = false

    private let context: NotchcastContext
    private let system: NoiseControlSystem
    private let commandIDs: [(id: String, request: NoiseControlRequest)]
    private var watch: AnyObject?
    private var offered: [NoiseControlRequest] = []
    private(set) var switchTask: Task<Void, Never>?
    private var operation = UUID()
    private(set) var isRunning = false

    init(context: NotchcastContext, system: NoiseControlSystem, commandIDs: [(id: String, request: NoiseControlRequest)]) {
        self.context = context
        self.system = system
        self.commandIDs = commandIDs
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        watch = system.watchOutput { [weak self] in self?.refresh() }
        refresh()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        watch = nil
        switchTask?.cancel()
        switchTask = nil
        operation = UUID()
        context.presenter.end(notice: Self.noticeID)
    }

    func refresh() {
        guard isRunning else { return }
        offered = NoiseControlPolicy.requests(offered: NoiseControlHeadset.modes(modelUID: system.outputModelUID()))
        context.setUnavailable(Set(commandIDs.filter { !offered.contains($0.request) }.map(\.id)))
    }

    /// A press while a switch runs is dropped: two walks of one menu would toggle it shut mid-read.
    func run(_ request: NoiseControlRequest) {
        guard isRunning, switchTask == nil, !Self.isWalking else { return }
        refresh()
        if offered.isEmpty { return show(.failure(NoiseControlFailure.noHeadset), for: request) }
        guard offered.contains(request) else { return show(.failure(NoiseControlFailure.modeUnavailable), for: request) }
        context.refreshPermission()
        guard context.isAccessibilityTrusted else {
            return show(.failure(NoiseControlFailure.needsAccessibility), for: request)
        }
        let operation = operation
        let switcher = system.switcher
        Self.isWalking = true
        switchTask = Task { [weak self] in
            let result: Result<NoiseControlMode, any Error>
            do { result = .success(try await switcher.run(request)) } catch { result = .failure(error) }
            Self.isWalking = false
            guard let self, !Task.isCancelled, self.isRunning, self.operation == operation else { return }
            self.switchTask = nil
            self.show(result, for: request)
        }
    }

    private func show(_ result: Result<NoiseControlMode, any Error>, for request: NoiseControlRequest) {
        let notice: IslandNotice
        switch result {
        case .success(let mode):
            let done = NoiseControlRequest.set(mode)
            notice = IslandNotice(id: Self.noticeID, symbol: done.symbol, text: done.title)
        case .failure(is CancellationError):
            return
        case .failure(let error):
            let text = (error as? NoiseControlFailure ?? .menuUnavailable).errorDescription ?? ""
            notice = IslandNotice(id: Self.noticeID, symbol: request.symbol, text: text, isFailure: true)
        }
        context.presenter.post(notice, onTap: nil)
    }
}
