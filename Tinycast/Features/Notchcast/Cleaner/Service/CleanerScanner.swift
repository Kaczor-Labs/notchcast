// Adapted from Dragos Tugui's Peel, SpaceRemoval.swift and SpaceReport.swift @ 20230794 (GPL-3.0).
import Foundation

struct CleanerScanner: Sendable {
    let fileSystem: any CleanerFileSystem
    var readGroups: @Sendable (URL) -> [String]? = CleanerRunningApps.applicationGroups
    var clock: @Sendable () -> Date = { .now }
    var monotonic: @Sendable () -> ContinuousClock.Instant = { .now }

    static let maxEntries = 20_000
    private static let budget: Duration = .seconds(2)

    @concurrent
    func scan(
        home: URL, apps: CleanerRunningApps,
        onItem: @MainActor @Sendable (CleanerItem) -> Void = { _ in }
    ) async throws -> CleanerPlan {
        try Task.checkCancellation()
        let extra = try additionalAreas(home: home)
        let appsWithGroups = extra.areas.contains(where: \.isSharedContainer) ? apps.includingGroups(read: readGroups) : apps
        var items = extra.blocked
        var snapshots: [URL: CleanerSnapshot] = [:]
        var seenRoots: Set<URL> = []
        var openFiles: Result<CleanerOpenFiles, Error>?
        for item in extra.blocked { await onItem(item) }

        for area in CleanerArea.userAreas(home: home) + extra.areas where seenRoots.insert(area.root).inserted {
            try Task.checkCancellation()
            let areaApps = area.isSharedContainer ? appsWithGroups : apps
            let candidates: [URL]
            do {
                candidates = try candidateURLs(in: area, apps: areaApps)
            } catch CleanerFileError.missing {
                continue
            } catch {
                try Task.checkCancellation()
                let item = CleanerItem(id: area.root, area: area, size: nil,
                                       standing: .locked(error as? CleanerHoldBack ?? .unreadable))
                items.append(item)
                await onItem(item)
                continue
            }

            if !candidates.isEmpty, openFiles == nil {
                openFiles = Result { try fileSystem.openFiles() }
                try Task.checkCancellation()
            }
            for url in candidates {
                try Task.checkCancellation()
                let item: CleanerItem
                do {
                    let snapshot = try snapshot(of: url, in: area)
                    let size = MeasuredSize(bytes: snapshot.entries.values.reduce(0) { $0 + $1.size })
                    let standing: CleanerItem.Standing
                    if let reason = hold(for: url, in: area, snapshot: snapshot, apps: areaApps) {
                        standing = .heldBack(reason)
                    } else if let reason = openFileHold(in: snapshot, row: url, area: area, openFiles: openFiles) {
                        standing = .heldBack(reason)
                    } else {
                        standing = area.needsOptIn ? .optional : .recommended
                        snapshots[url] = snapshot
                    }
                    item = CleanerItem(id: url, area: area, size: size, standing: standing)
                } catch {
                    try Task.checkCancellation()
                    item = CleanerItem(id: url, area: area, size: nil,
                                       standing: .locked(error as? CleanerHoldBack ?? .unreadable))
                }
                items.append(item)
                await onItem(item)
            }
        }
        try Task.checkCancellation()
        return CleanerPlan(items: items, snapshots: snapshots)
    }

    private func openFileHold(
        in snapshot: CleanerSnapshot, row: URL, area: CleanerArea, openFiles: Result<CleanerOpenFiles, Error>?
    ) -> CleanerHoldBack? {
        guard case .success(let openFiles) = openFiles else { return .unreadable }
        return openFiles.hold(on: snapshot, row: row, checkingHeld: area.kind != .caches)
    }

    private func candidateURLs(in area: CleanerArea, apps: CleanerRunningApps) throws -> [URL] {
        _ = try directoryIdentities(to: area.root)
        let names = try fileSystem.children(of: area.root, limit: Self.maxEntries).sorted()
        let children = try names.map { try child($0, of: area.root) }
            .filter { !isExcluded($0, in: area, ownNames: apps.own) }
        guard area.filesOnly else { return children }

        var pending = Array(children.reversed())
        var files: [URL] = []
        var remaining = Self.maxEntries
        let deadline = monotonic().advanced(by: Self.budget)
        let root = try fileSystem.inspect(area.root)
        while let url = pending.popLast() {
            try Task.checkCancellation()
            guard remaining > 0, monotonic() < deadline else { throw CleanerHoldBack.scanLimit }
            remaining -= 1
            guard let file = try? fileSystem.inspect(url), file.facts.isDirectory, !file.facts.isSymbolicLink
            else {
                files.append(url)
                continue
            }
            guard file.identity.device == root.identity.device, !CleanerProtectedPaths.isProtected(url) else { continue }
            let names = try fileSystem.children(of: url, limit: remaining - pending.count).sorted()
            pending += try names.reversed().map { try child($0, of: url) }
                .filter { !isExcluded($0, in: area, ownNames: apps.own) }
        }
        return files
    }

    func directoryIdentities(to root: URL) throws -> [CleanerFile.Identity] {
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

    func parentIdentities(of url: URL, in area: CleanerArea) throws -> [CleanerFile.Identity] {
        guard area.contains(url) else { throw CleanerHoldBack.unsafePath }
        let parent = url.deletingLastPathComponent()
        let identities = try directoryIdentities(to: parent)
        if area.filesOnly {
            let rootIndex = area.root.pathComponents.count - 1
            let chain = identities[rootIndex...]
            guard chain.allSatisfy({ $0.device == chain.first?.device }) else { throw CleanerHoldBack.unsafePath }
            var path = parent
            while path.path != area.root.path {
                guard !CleanerProtectedPaths.isProtected(path) else { throw CleanerHoldBack.protectedData }
                path = path.deletingLastPathComponent()
            }
        }
        return identities
    }

    func snapshot(of url: URL, in area: CleanerArea) throws -> CleanerSnapshot {
        let parents = try parentIdentities(of: url, in: area)
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
            if let reason = CleanerPolicy.protection(for: file, in: area, isRow: path == url) { throw reason }
            if path == url {
                guard !area.filesOnly || file.isRegularFile else { throw CleanerHoldBack.unsafePath }
                guard area.kind != .savedState || file.facts.isDirectory else { throw CleanerHoldBack.unsafePath }
            }
            entries[path] = file
            if file.facts.isDirectory {
                let names = try fileSystem.children(of: path, limit: remaining - pending.count)
                pending += try names.map { try child($0, of: path) }
            }
        }
        return CleanerSnapshot(parents: parents, entries: entries)
    }

    func hold(
        for url: URL, in area: CleanerArea, snapshot: CleanerSnapshot, apps: CleanerRunningApps
    ) -> CleanerHoldBack? {
        if area.kind == .mailDownloads { return .mailDownloadMayContainEdits }
        if apps.holds(area.ownerName(of: url)) { return .runningApp }
        if snapshot.entries.keys.contains(where: { CleanerPolicy.repositoryMarkers.contains($0.lastPathComponent.lowercased()) }) {
            return .holdsRepository
        }
        if area.isSharedContainer, apps.groupMembershipUnknown { return .unreadable }
        let now = clock()
        if snapshot.entries.values.contains(where: { now.timeIntervalSince($0.modified) < area.minimumAge }) {
            return area.kind == .savedState ? .recentSavedState : .recentWrite
        }
        if area.kind == .browserVersions {
            guard let file = snapshot.entries[url],
                (try? CleanerBrowserVersions.canMove(url, file: file, in: area, fileSystem: fileSystem)) == true
            else { return .activeBrowserVersion }
        }
        return nil
    }

    func isExcluded(_ url: URL, in area: CleanerArea, ownNames: Set<String>) -> Bool {
        let name = url.lastPathComponent
        let folded = name.lowercased()
        if [".ds_store", ".localized"].contains(folded) || ownNames.contains(CleanerPolicy.appKey(area.ownerName(of: url)))
            || ownNames.contains(CleanerPolicy.appKey(CleanerPolicy.groupOwner(area.ownerName(of: url)))) {
            return true
        }
        switch area.kind {
        case .caches:
            return CleanerProtectedPaths.isAppleCache(name) || Self.browserCacheParents.contains(folded)
        case .logs:
            return CleanerProtectedPaths.isCodexLog(url)
                || (!area.filesOnly && (folded == "diagnosticreports" || (area.owner == nil && folded == "homebrew")))
        case .savedState:
            return url.pathExtension != "savedState"
                || CleanerProtectedPaths.isAppleCache(url.deletingPathExtension().lastPathComponent)
        case .browserVersions:
            return CleanerBrowserVersions.version(name) == nil
        default:
            return false
        }
    }

    func child(_ name: String, of parent: URL) throws -> URL {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.utf8.contains(0) else {
            throw CleanerHoldBack.unsafePath
        }
        return parent.appending(component: name, directoryHint: .notDirectory)
    }
}
