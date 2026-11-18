import Foundation

/// One archive from listing to its place beside the archive; every program call goes through `run`.
nonisolated struct ArchiveExtractor: Sendable {
    var locate: @Sendable (String) async -> URL?
    var run: @Sendable (URL, [String]) async throws -> ArchiveProcessResult

    /// Asked once when keeping the archive does not fit; gets HatchZip's in-place plan, true goes ahead.
    typealias AskInPlace = @Sendable (_ plan: String) async -> Bool

    /// The final file or folder. `onInPlace` runs before the archive starts being consumed.
    @concurrent
    func extract(
        _ job: ArchiveJob, askInPlace: AskInPlace, onInPlace: @Sendable () async -> Void
    ) async throws -> URL? {
        guard var route = ArchiveRoute(fileName: job.name) else { throw ArchiveFailure.notArchive(job.name) }
        if route.engine == .hatchzip, job.name.lowercased().hasSuffix(".zip"), hasLegacyNames(job.archive),
            await locate(ArchiveTool.unar.name) != nil
        {
            route = ArchiveRoute(engine: .unar, stem: route.stem)
        }
        let tools = ArchiveCommandLine.tools(route.engine)
        let extractor = try await find(tools.extract)
        if let lister = tools.list, let arguments = ArchiveCommandLine.list(route.engine, archive: job.archive) {
            let listed = try await run(try await find(lister), arguments)
            if let failure = route.engine == .hatchzip ? ArchiveFailure.hatchzip(listed) : .tool(listed) {
                throw failure
            }
            let listing = route.engine == .unar ? try ArchiveListing.lsar(Data(listed.output.utf8))
                : route.engine == .bsdtar ? ArchiveListing.bsdtar(listed.output) : ArchiveListing.hatchzip(listed.output)
            if let refusal = ArchiveSafety.refusal(for: listing, archiveSize: Self.size(job.archive)) {
                throw ArchiveFailure.unsafe(refusal)
            }
        }
        // Only HatchZip resumes into what an earlier run left; any other engine starts clean.
        if route.engine != .hatchzip { try? FileManager.default.removeItem(at: job.staging) }
        try FileManager.default.createDirectory(at: job.staging, withIntermediateDirectories: true)
        let program = route.engine.isSingleStream ? URL(filePath: "/bin/sh") : extractor
        func runEngine(inPlace: Bool) async throws -> ArchiveProcessResult {
            try await run(program, ArchiveCommandLine.extract(
                route.engine, tool: extractor, archive: job.archive, staging: job.staging, stem: route.stem,
                inPlace: inPlace))
        }
        var result = try await runEngine(inPlace: job.inPlace)
        if route.engine == .hatchzip, !job.inPlace, result.status == ArchiveFailure.hatchzipNoSpace {
            let plan = try await run(extractor, ArchiveCommandLine.check(archive: job.archive, staging: job.staging))
            guard await askInPlace(plan.output) else {
                try? FileManager.default.removeItem(at: job.staging)
                throw ArchiveFailure.hatchzip(result) ?? .failed("")
            }
            await onInPlace()
            result = try await runEngine(inPlace: true)
        }
        if route.engine == .hatchzip, result.status == ArchiveFailure.hatchzipPaused { throw CancellationError() }
        if let failure = route.engine == .hatchzip ? ArchiveFailure.hatchzip(result) : .tool(result) {
            throw failure
        }
        return try place(job, stem: route.stem)
    }

    /// After a stop or a failure once writing began: the archive whole again, files kept only when in place.
    @concurrent
    func abandon(_ job: ArchiveJob) async -> URL? {
        guard FileManager.default.fileExists(atPath: job.staging.path) else { return nil }
        if ArchiveRoute(fileName: job.name)?.engine == .hatchzip, let hatchzip = await locate(ArchiveTool.hatchzip.name) {
            _ = try? await run(hatchzip, ArchiveCommandLine.restore(archive: job.archive, staging: job.staging))
        }
        guard job.inPlace, let stem = ArchiveRoute(fileName: job.name)?.stem else {
            try? FileManager.default.removeItem(at: job.staging)
            return nil
        }
        return try? place(job, stem: stem)
    }

    /// Moves the staged items out by rename, so no byte is copied and nothing is overwritten.
    func place(_ job: ArchiveJob, stem: String) throws -> URL? {
        let files = FileManager.default
        let folder = job.archive.deletingLastPathComponent()
        let items = (try? files.contentsOfDirectory(atPath: job.staging.path)) ?? []
        let taken = { (name: String) in files.fileExists(atPath: folder.appending(path: name).path) }
        switch ArchivePlacement.plan(items: items.sorted(), stem: stem, taken: taken) {
        case .empty:
            try? files.removeItem(at: job.staging)
            return nil
        case .item(let item, let name):
            let target = folder.appending(path: name)
            try files.moveItem(at: job.staging.appending(path: item), to: target)
            try? files.removeItem(at: job.staging)
            return target
        case .folder(let name):
            let target = folder.appending(path: name, directoryHint: .isDirectory)
            try files.moveItem(at: job.staging, to: target)
            return target
        }
    }

    private func find(_ tool: ArchiveTool) async throws -> URL {
        guard let url = await locate(tool.name) else { throw ArchiveFailure.missingTool(tool) }
        return url
    }

    private static func size(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func hasLegacyNames(_ archive: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: archive) else { return false }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return false }
        let start = end > UInt64(ZIPNameEncoding.tailLength) ? end - UInt64(ZIPNameEncoding.tailLength) : 0
        guard (try? handle.seek(toOffset: start)) != nil, let tail = try? handle.readToEnd(),
            let directory = ZIPNameEncoding.directory(tail: tail), directory.size <= 64 << 20,
            (try? handle.seek(toOffset: directory.offset)) != nil,
            let names = try? handle.read(upToCount: Int(directory.size))
        else { return false }
        return ZIPNameEncoding.hasLegacyNames(directory: names)
    }
}
