import Foundation
import Observation

@MainActor
@Observable
final class CleanerSession {
    enum Phase {
        case needsAccess
        case scanning
        case review
        case cleaning
        case done
        case scanFailed
    }

    private(set) var phase: Phase = .needsAccess
    private(set) var items: [CleanerItem] = []
    private(set) var selection: CleanerSelection?
    private(set) var report: CleanerReport?

    private let area: CleanerArea
    private let runner: CleanerRunner
    private let hasAccess: @MainActor () -> Bool
    private var plan: CleanerPlan?

    init(area: CleanerArea, runner: CleanerRunner, hasAccess: @escaping @MainActor () -> Bool) {
        self.area = area
        self.runner = runner
        self.hasAccess = hasAccess
    }

    func open() async {
        guard phase != .scanning, phase != .cleaning else { return }
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
            let scanned = try await runner.scanner.scan(area, apps: runner.runningApps()) { [weak self] item in
                self?.items.append(item)
            }
            try Task.checkCancellation()
            plan = scanned
            selection = scanned.defaultSelection
            phase = .review
        } catch {
            items = []
            phase = .scanFailed
        }
    }

    func setChecked(_ id: CleanerItem.ID, checked: Bool) {
        guard phase == .review, let plan else { return }
        selection?.set(id, checked: checked, in: plan)
    }

    func clean(confirm: @MainActor (CleanerSelection) async -> Bool) async {
        guard phase == .review, let plan, let selection, !selection.checked.isEmpty else { return }
        phase = .cleaning
        guard await confirm(selection), !Task.isCancelled else {
            phase = .review
            return
        }
        guard hasAccess() else {
            phase = .needsAccess
            return
        }
        report = await runner.run(plan, selection: selection)
        phase = .done
    }

    static func live() -> CleanerSession {
        CleanerSession(
            area: CleanerArea(home: FileManager.default.homeDirectoryForCurrentUser),
            runner: CleanerRunner(
                scanner: CleanerScanner(fileSystem: LiveCleanerFileSystem()), runningApps: CleanerRunningApps.live),
            hasAccess: Permissions.hasFullDiskAccess)
    }
}
