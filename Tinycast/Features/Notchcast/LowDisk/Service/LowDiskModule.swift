import AppKit

/// Warns once on the island and checks for recovery while the glyph shows.
@MainActor
final class LowDiskModule: NotchcastModule {
    typealias Reader = @Sendable () async throws -> Int64

    static let noticeID = LowDiskPolicy.statusID
    static let symbol = LowDiskPolicy.symbol

    private let context: NotchcastContext
    private let read: Reader
    private let isDisplayAsleep: @MainActor () -> Bool
    private var policy = LowDiskPolicy()
    private var postedStatus: IslandStatus?
    private var isLow = false
    private var warnedWithAction = false
    private var menuTitle: String?
    private var wakeObserver: NotificationCenter.ObservationToken?
    private var timer: Task<Void, Never>?
    private(set) var checking: Task<Void, Never>?
    private(set) var reporting: Task<Void, Never>?
    private var operation = UUID()
    private(set) var isRunning = false

    init(
        context: NotchcastContext, read: @escaping Reader = LowDiskModule.readStartupDisk,
        isDisplayAsleep: @escaping @MainActor () -> Bool = LowDiskModule.isMainDisplayAsleep
    ) {
        self.context = context
        self.read = read
        self.isDisplayAsleep = isDisplayAsleep
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        policy = LowDiskPolicy(hasWarned: context.defaults.bool(forKey: LowDiskPolicy.warnedKey))
        let workspace = NSWorkspace.shared
        wakeObserver = workspace.notificationCenter.addObserver(of: workspace, for: .screensDidWake) { [weak self] _ in
            await self?.check()
        }
        context.cleanUp.onChange = { [weak self] in self?.updateCleanUp() }
        scheduleChecks()
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
        reporting?.cancel()
        reporting = nil
        operation = UUID()
        context.cleanUp.onChange = nil
        isLow = false
        warnedWithAction = false
        updateCleanUp()
        setStatus(nil)
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
        reporting?.cancel()
        let operation = operation
        let read = read
        let task = Task { [weak self] in
            let free = try? await read()
            guard let self, self.isRunning, !Task.isCancelled else { return }
            self.reporting = nil
            if let free, free >= 0, self.policy.hasWarned, self.operation == operation {
                self.checking?.cancel()
                self.checking = nil
                self.apply(free)
            }
            let notice = free.map {
                IslandNotice(id: Self.noticeID, symbol: Self.symbol, text: LowDiskPolicy.available(free: $0))
            } ?? IslandNotice(
                id: Self.noticeID, symbol: Self.symbol,
                text: String(localized: "Couldn’t read disk space", table: "NotchcastLowDisk"), isFailure: true)
            self.warnedWithAction = false
            self.context.presenter.post(notice, onTap: nil)
        }
        reporting = task
        return task
    }

    private func apply(_ free: Int64) {
        guard free >= 0, !isDisplayAsleep() else { return }
        let stored = context.defaults.object(forKey: LowDiskPolicy.thresholdKey) as? Int
        let threshold = LowDiskPolicy.thresholdGB(stored: stored)
        isLow = free < LowDiskPolicy.bytes(gigabytes: threshold)
        updateCleanUp()
        let hadWarned = policy.hasWarned
        let warns = policy.shouldWarn(free: free, thresholdGB: threshold, displayAsleep: false)
        if policy.hasWarned != hadWarned {
            context.defaults.set(policy.hasWarned, forKey: LowDiskPolicy.warnedKey)
        }
        if warns {
            warnedWithAction = menuTitle != nil
            let tap: @MainActor () -> Void = { [weak self] in self?.openCleanUp() }
            context.presenter.post(
                IslandNotice(id: Self.noticeID, symbol: Self.symbol,
                             text: LowDiskPolicy.warning(free: free, actionTitle: menuTitle), isFailure: true),
                onTap: warnedWithAction ? tap : nil)
        }
        setStatus(policy.status)
    }

    private func updateCleanUp() {
        let title = isLow ? context.cleanUp.title : nil
        guard title != menuTitle else { return }
        menuTitle = title
        if warnedWithAction {
            warnedWithAction = false
            context.presenter.end(notice: Self.noticeID)
        }
        let rows = title.map { [IslandMenuRow(id: Self.noticeID, title: $0)] } ?? []
        context.presenter.setMenuRows(rows, owner: Self.noticeID) { [weak self] _ in self?.openCleanUp() }
    }

    private func openCleanUp() {
        guard isLow else { return }
        context.cleanUp.open()
    }

    private func scheduleChecks() {
        timer?.cancel()
        guard isRunning else { return }
        let interval = postedStatus == nil ? LowDiskPolicy.checkInterval : .seconds(15)
        timer = Task { [weak self] in
            while !Task.isCancelled, (try? await Self.waitForCheck(interval)) != nil {
                guard !Task.isCancelled, let self else { return }
                await self.check()?.value
            }
        }
    }

    private func setStatus(_ status: IslandStatus?) {
        guard status != postedStatus else { return }
        postedStatus = status
        scheduleChecks()
        let tap: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            if menuTitle != nil { openCleanUp() }
            else { showFreeSpace() }
        }
        context.presenter.setStatus(status, for: Self.noticeID, onTap: status == nil ? nil : tap)
    }
}
