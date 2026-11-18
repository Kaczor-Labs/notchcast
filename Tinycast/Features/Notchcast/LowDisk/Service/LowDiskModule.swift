import AppKit

/// Reads the startup disk at start, on wake and every half hour, and warns once on the island.
@MainActor
final class LowDiskModule: NotchcastModule {
    typealias Reader = @Sendable () async throws -> Int64

    static let noticeID = "lowDisk"
    static let symbol = "internaldrive"

    private let context: NotchcastContext
    private let read: Reader
    private var policy = LowDiskPolicy()
    private var wakeObserver: NotificationCenter.ObservationToken?
    private var timer: Task<Void, Never>?
    private(set) var checking: Task<Void, Never>?
    private var operation = UUID()
    private(set) var isRunning = false

    init(context: NotchcastContext, read: @escaping Reader = LowDiskModule.readStartupDisk) {
        self.context = context
        self.read = read
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        policy = LowDiskPolicy(hasWarned: context.defaults.bool(forKey: LowDiskPolicy.warnedKey))
        let workspace = NSWorkspace.shared
        wakeObserver = workspace.notificationCenter.addObserver(of: workspace, for: .didWake) { [weak self] _ in
            self?.check()
        }
        timer = Task { [weak self] in
            while (try? await Task.sleep(for: LowDiskPolicy.checkInterval, tolerance: .seconds(60))) != nil {
                self?.check()
            }
        }
        check()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        timer?.cancel()
        timer = nil
        checking?.cancel()
        checking = nil
        operation = UUID()
        context.presenter.end(notice: Self.noticeID)
    }

    /// A new check replaces one in flight, so only the latest reading reaches the policy.
    @discardableResult
    func check() -> Task<Void, Never>? {
        guard isRunning else { return nil }
        checking?.cancel()
        let operation = UUID()
        self.operation = operation
        let read = read
        let task = Task { [weak self] in
            let free = try? await read()
            guard let self, let free, !Task.isCancelled, self.isRunning, self.operation == operation else { return }
            self.checking = nil
            self.apply(free)
        }
        checking = task
        return task
    }

    /// The launcher command: free space on demand, whatever the warning's state.
    @discardableResult
    func showFreeSpace() -> Task<Void, Never>? {
        guard isRunning else { return nil }
        let read = read
        return Task { [weak self] in
            let free = try? await read()
            guard let self, self.isRunning else { return }
            let notice = free.map {
                IslandNotice(id: Self.noticeID, symbol: Self.symbol, text: LowDiskPolicy.available(free: $0))
            } ?? IslandNotice(
                id: Self.noticeID, symbol: Self.symbol,
                text: String(localized: "Couldn’t read disk space", table: "NotchcastLowDisk"), isFailure: true)
            self.context.presenter.post(notice, onTap: nil)
        }
    }

    private func apply(_ free: Int64) {
        let stored = context.defaults.object(forKey: LowDiskPolicy.thresholdKey) as? Int
        let warns = policy.shouldWarn(free: free, thresholdGB: LowDiskPolicy.thresholdGB(stored: stored))
        context.defaults.set(policy.hasWarned, forKey: LowDiskPolicy.warnedKey)
        guard warns else { return }
        context.presenter.post(
            IslandNotice(id: Self.noticeID, symbol: Self.symbol, text: LowDiskPolicy.warning(free: free),
                         isFailure: true),
            onTap: nil)
    }
}
