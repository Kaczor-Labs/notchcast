// Adapted from Dragos Tugui's Peel, SpaceRemoval.swift and SpaceReport.swift @ 20230794 (GPL-3.0).
import Foundation

struct CleanerScanner: Sendable {
    let fileSystem: any CleanerFileSystem
    var clock: @Sendable () -> Date = { .now }
    var monotonic: @Sendable () -> ContinuousClock.Instant = { .now }

    private static let maxEntries = 20_000
    private static let budget: Duration = .seconds(2)

    @concurrent
    func scan(
        _ area: CleanerArea, apps: CleanerRunningApps,
        onItem: @MainActor @Sendable (CleanerItem) -> Void = { _ in }
    ) async throws -> CleanerPlan {
        let parents = try parentIdentities(in: area)
        let names = try fileSystem.children(of: area.root, limit: Self.maxEntries)
        var items: [CleanerItem] = []
        var snapshots: [URL: CleanerSnapshot] = [:]

        for name in names.sorted() {
            try Task.checkCancellation()
            guard !CleanerPolicy.isExcluded(name, ownNames: apps.own) else { continue }
            let url = try child(name, of: area.root)
            let item: CleanerItem
            do {
                let snapshot = try snapshot(of: url, in: area, parents: parents)
                let size = MeasuredSize(bytes: snapshot.entries.values.reduce(0) { $0 + $1.size })
                let standing: CleanerItem.Standing
                if apps.holds(url) {
                    standing = .heldBack(.runningApp)
                } else if hasRecentWrite(snapshot, now: clock()) {
                    standing = .heldBack(.recentWrite)
                } else {
                    standing = .recommended
                    snapshots[url] = snapshot
                }
                item = CleanerItem(id: url, size: size, standing: standing)
            } catch let reason as CleanerHoldBack {
                item = CleanerItem(id: url, size: nil, standing: .locked(reason))
            } catch CleanerFileError.missing, CleanerFileError.unreadable {
                item = CleanerItem(id: url, size: nil, standing: .locked(.unreadable))
            }
            items.append(item)
            await onItem(item)
        }
        try Task.checkCancellation()
        return CleanerPlan(area: area, items: items, snapshots: snapshots)
    }

    func parentIdentities(in area: CleanerArea) throws -> [CleanerFile.Identity] {
        let root = area.root
        guard root.isFileURL, root == root.standardizedFileURL else { throw CleanerHoldBack.unsafePath }
        var paths = [root]
        while let path = paths.last, path.path != "/" {
            paths.append(path.deletingLastPathComponent())
        }
        return try paths.reversed().map {
            let file = try fileSystem.inspect($0)
            guard file.facts.isDirectory, !file.facts.isSymbolicLink else { throw CleanerHoldBack.unsafePath }
            return file.identity
        }
    }

    func snapshot(of url: URL, in area: CleanerArea) throws -> CleanerSnapshot {
        try snapshot(of: url, in: area, parents: parentIdentities(in: area))
    }

    private func snapshot(
        of url: URL, in area: CleanerArea, parents: [CleanerFile.Identity]
    ) throws -> CleanerSnapshot {
        guard area.contains(url) else { throw CleanerHoldBack.unsafePath }
        var remaining = Self.maxEntries
        let deadline = monotonic().advanced(by: Self.budget)
        var pending = [url]
        var entries: [URL: CleanerFile] = [:]
        while let path = pending.popLast() {
            try Task.checkCancellation()
            guard remaining > 0, monotonic() < deadline else { throw CleanerHoldBack.scanLimit }
            remaining -= 1
            guard !CleanerProtectedPaths.isProtected(path) else { throw CleanerHoldBack.protectedData }
            let file = try fileSystem.inspect(path)
            guard file.identity.device == parents.last?.device else { throw CleanerHoldBack.unsafePath }
            if let reason = CleanerPolicy.protection(for: file, in: area) { throw reason }
            entries[path] = file
            if file.facts.isDirectory {
                let names = try fileSystem.children(of: path, limit: remaining - pending.count)
                pending += try names.map { try child($0, of: path) }
            }
        }
        return CleanerSnapshot(parents: parents, entries: entries)
    }

    func hasRecentWrite(_ snapshot: CleanerSnapshot, now: Date) -> Bool {
        snapshot.entries.values.contains { now.timeIntervalSince($0.modified) < CleanerPolicy.recentWrite }
    }

    private func child(_ name: String, of parent: URL) throws -> URL {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.utf8.contains(0) else {
            throw CleanerHoldBack.unsafePath
        }
        return parent.appending(component: name, directoryHint: .notDirectory)
    }
}
