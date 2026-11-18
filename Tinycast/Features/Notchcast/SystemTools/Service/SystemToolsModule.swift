import CoreGraphics
import Foundation

/// Opens the process picker; runs one network test at a time, progress and result on the island.
@MainActor
final class SystemToolsModule: NotchcastModule {
    static let networkNoticeID = "systemTools.network"
    static let networkSymbol = "gauge.with.dots.needle.67percent"
    static let escapeKeyCode: Int64 = 53
    /// A result is read, not glanced at, so it stays past the stock message dwell.
    static let resultSeconds: TimeInterval = 8

    let context: NotchcastContext
    let system: SystemToolsSystem
    /// The one address lookup, network list or password read in flight.
    var lookup: Task<Void, Never>?
    private var closePicker: (@MainActor () -> Void)?
    private var networkTask: Task<Void, Never>?
    private var escapeTap: UUID?
    private var operation = UUID()
    private(set) var isRunning = false

    init(context: NotchcastContext, system: SystemToolsSystem) {
        self.context = context
        self.system = system
    }

    var isTestingNetwork: Bool { networkTask != nil }

    func start() {
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        closePicker?()
        closePicker = nil
        lookup?.cancel()
        lookup = nil
        guard isTestingNetwork else { return }
        endNetworkTest()
        context.presenter.end(notice: Self.networkNoticeID)
    }

    func killProcess() {
        guard isRunning else { return }
        present(KillProcessSession(system: system, context: context))
    }

    func present(_ picker: any SystemToolsPicking) {
        closePicker?()
        closePicker = system.presentPicker(picker, context.surfaces)
    }

    func testNetwork() {
        guard isRunning, !isTestingNetwork else { return }
        let operation = UUID()
        self.operation = operation
        context.presenter.post(
            IslandNotice(
                id: Self.networkNoticeID, symbol: Self.networkSymbol,
                text: String(localized: "Testing network…", table: "NotchcastSystemTools"),
                progress: IslandProgress(fraction: nil)),
            onTap: { [weak self] in self?.cancelNetworkTest() })
        escapeTap = context.subscribe(
            NotchcastTap(
                switchID: SystemToolsAddon.switchID, mask: NotchcastTapPolicy.mask(for: .keyDown),
                handler: .observe { [weak self] event in
                    if event.keyCode == Self.escapeKeyCode { self?.cancelNetworkTest() }
                }))
        let run = system.runNetworkQuality
        networkTask = Task { [weak self] in
            let outcome: Result<NetworkQualityResult, any Error>
            do {
                outcome = .success(try NetworkQualityResult.parse(try await run()))
            } catch {
                outcome = .failure(error)
            }
            guard let self, self.operation == operation, isRunning else { return }
            endNetworkTest()
            report(outcome)
        }
    }

    func cancelNetworkTest() {
        guard isTestingNetwork else { return }
        endNetworkTest()
        post(String(localized: "Network Test Cancelled", table: "NotchcastSystemTools"), failure: false)
    }

    private func endNetworkTest() {
        networkTask?.cancel()
        networkTask = nil
        operation = UUID()
        if let escapeTap { context.unsubscribe(escapeTap) }
        escapeTap = nil
    }

    private func report(_ outcome: Result<NetworkQualityResult, any Error>) {
        switch outcome {
        case .success(let result):
            context.presenter.post(
                IslandNotice(
                    id: Self.networkNoticeID, symbol: Self.networkSymbol, text: result.summary,
                    seconds: Self.resultSeconds),
                onTap: nil)
        case .failure:
            post(String(localized: "Network Test Failed", table: "NotchcastSystemTools"), failure: true)
        }
    }

    private func post(_ text: String, failure: Bool) {
        context.presenter.post(
            IslandNotice(id: Self.networkNoticeID, symbol: Self.networkSymbol, text: text, isFailure: failure),
            onTap: nil)
    }
}
