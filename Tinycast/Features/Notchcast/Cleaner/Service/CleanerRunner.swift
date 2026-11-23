// Adapted from Dragos Tugui's Peel, SpaceRemoval.swift and TrashService.swift @ 20230794 (GPL-3.0).
import Foundation

struct CleanerRunner: Sendable {
    let scanner: CleanerScanner
    let runningApps: @MainActor @Sendable () -> CleanerRunningApps

    @concurrent
    func run(
        _ plan: CleanerPlan, selection: CleanerSelection,
        onProgress: @MainActor @Sendable (Int) -> Void = { _ in }
    ) async -> CleanerReport {
        var report = CleanerReport()
        var openFiles = OpenFiles()
        for item in plan.items where selection.checked.contains(item.id) {
            do {
                try Task.checkCancellation()
                let outcome = try await move(item, in: plan, openFiles: &openFiles)
                report.entries.append(.init(id: item.id, outcome: outcome))
            } catch is CancellationError {
                report.cancelled = true
                break
            } catch {
                report.entries.append(.init(id: item.id, outcome: .failed))
            }
            await onProgress(report.entries.count)
        }
        return report
    }

    private struct OpenFiles {
        var identities: Set<CleanerFile.Identity> = []
        var expires: ContinuousClock.Instant?
    }

    private func move(
        _ item: CleanerItem, in plan: CleanerPlan, openFiles: inout OpenFiles
    ) async throws -> CleanerReport.Outcome {
        let url = item.id
        let area = item.area
        guard item.standing.isSelectable, area.contains(url), let scanned = plan.snapshots[url] else {
            return .skipped(.heldBack(.unsafePath))
        }

        let apps = await runningApps()
        if scanner.isExcluded(url, in: area, ownNames: apps.own) {
            return .skipped(.heldBack(.protectedData))
        }
        if apps.holds(area.ownerName(of: url)) { return .skipped(.heldBack(.runningApp)) }

        do {
            guard try scanner.parentIdentities(of: url, in: area) == scanned.parents else {
                return .skipped(.changed)
            }
            guard try scanner.fileSystem.inspect(url) == scanned.entries[url] else { return .skipped(.changed) }
            if openFiles.expires.map({ scanner.monotonic() >= $0 }) != false {
                let started = scanner.monotonic()
                openFiles.identities = try scanner.fileSystem.openFiles()
                openFiles.expires = started.advanced(by: .seconds(1))
            }
            let refreshAfterWalk = area.kind == .browserVersions
            let latestApps = area.kind == .caches || refreshAfterWalk ? apps : await runningApps()
            let appsBeforeWalk = area.isSharedContainer ? latestApps.includingGroups(read: scanner.readGroups) : latestApps
            let current = try scanner.snapshot(of: url, in: area)
            guard current == scanned else { return .skipped(.changed) }
            if current.entries.values.contains(where: { openFiles.identities.contains($0.identity) }) {
                return .skipped(.heldBack(.openFile))
            }
            let currentApps = refreshAfterWalk ? await runningApps() : appsBeforeWalk
            if scanner.isExcluded(url, in: area, ownNames: currentApps.own) {
                return .skipped(.heldBack(.protectedData))
            }
            if refreshAfterWalk, try scanner.snapshot(of: url, in: area) != scanned {
                return .skipped(.changed)
            }
            if let reason = scanner.hold(for: url, in: area, snapshot: current, apps: currentApps) {
                return .skipped(.heldBack(reason))
            }

            try Task.checkCancellation()
            guard try scanner.parentIdentities(of: url, in: area) == scanned.parents,
                try scanner.fileSystem.inspect(url) == scanned.entries[url]
            else { return .skipped(.changed) }
            try scanner.fileSystem.trash(url)
            return .trashed(item.size)
        } catch CleanerFileError.missing {
            return .skipped(.missing)
        } catch CleanerFileError.unreadable {
            return .skipped(.heldBack(.unreadable))
        } catch let reason as CleanerHoldBack {
            return .skipped(.heldBack(reason))
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return .skipped(.missing)
        }
    }
}
