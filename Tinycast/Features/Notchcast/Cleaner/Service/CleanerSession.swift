import Foundation
import Observation

@MainActor
@Observable
final class CleanerSession {
    enum Phase {
        case idle
        case needsAccess
        case scanning
        case review
        case confirming
        case cleaning
        case done
        case scanFailed
    }

    private(set) var phase: Phase = .idle
    private(set) var items: [CleanerItem] = []
    private(set) var selection: CleanerSelection?
    private(set) var report: CleanerReport?

    var selectedBytes: Int64 {
        guard let selection else { return 0 }
        return items.reduce(0) { sum, item in
            sum + (selection.checked.contains(item.id) ? item.size?.bytes ?? 0 : 0)
        }
    }

    private let home: URL
    private let runner: CleanerRunner
    private let hasAccess: @MainActor () -> Bool
    private var plan: CleanerPlan?
    @ObservationIgnored private var scanOperation = 0

    init(home: URL, runner: CleanerRunner, hasAccess: @escaping @MainActor () -> Bool) {
        self.home = home
        self.runner = runner
        self.hasAccess = hasAccess
    }

    func open() async {
        guard phase != .confirming, phase != .cleaning else { return }
        scanOperation += 1
        let operation = scanOperation
        items = []
        plan = nil
        selection = nil
        report = nil
        guard hasAccess() else {
            phase = .needsAccess
            return
        }
        phase = .scanning
        do {
            try Task.checkCancellation()
            let scanned = try await runner.scanner.scan(home: home, apps: runner.runningApps()) { [weak self] item in
                guard let self, self.scanOperation == operation, !Task.isCancelled else { return }
                self.items.append(item)
            }
            guard scanOperation == operation else { return }
            try Task.checkCancellation()
            plan = scanned
            selection = scanned.defaultSelection
            phase = .review
        } catch {
            guard scanOperation == operation else { return }
            items = []
            phase = error is CancellationError || Task.isCancelled ? .idle : .scanFailed
        }
    }

    func setChecked(_ id: CleanerItem.ID, checked: Bool) {
        guard phase == .review, let plan else { return }
        selection?.set(id, checked: checked, in: plan)
    }

    func clean(
        onProgress: @escaping @MainActor @Sendable (Int, Int) -> Void = { _, _ in },
        confirm: @MainActor (CleanerSelection) async -> Bool
    ) async {
        guard phase == .review, let plan, let selection, !selection.checked.isEmpty else { return }
        phase = .confirming
        guard await confirm(selection), !Task.isCancelled else {
            phase = .review
            return
        }
        guard hasAccess() else {
            phase = .needsAccess
            return
        }
        phase = .cleaning
        let count = selection.checked.count
        onProgress(0, count)
        report = await runner.run(plan, selection: selection) { completed in
            onProgress(completed, count)
        }
        phase = .done
    }

    static func live() -> CleanerSession {
        CleanerSession(
            home: FileManager.default.homeDirectoryForCurrentUser,
            runner: CleanerRunner(
                scanner: CleanerScanner(fileSystem: LiveCleanerFileSystem()), runningApps: CleanerRunningApps.live),
            hasAccess: Permissions.hasFullDiskAccess)
    }
}
