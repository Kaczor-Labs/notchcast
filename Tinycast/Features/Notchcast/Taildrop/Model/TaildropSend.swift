import Foundation

nonisolated struct TaildropOutput: Equatable, Sendable {
    var status: Int32 = 0
    var output = ""
    var errors = ""
}

/// Every outside fact a send needs, injected so a harness runs it with no CLI, Finder or disk.
nonisolated struct TaildropSystem: Sendable {
    /// The `tailscale` executable, nil when it is not installed.
    let cli: @Sendable () -> String?
    /// Runs a tool to its end; a cancelled task ends the tool and throws `CancellationError`.
    let run: @Sendable (_ executable: String, _ arguments: [String]) async throws -> TaildropOutput
    let finderSelection: @Sendable () async throws -> [String]
    /// Nil for a path that no longer exists.
    let isFolder: @Sendable (String) -> Bool?
    let makeScratch: @Sendable () throws -> String
    let remove: @Sendable (String) -> Void
}

nonisolated enum TaildropSend {
    static let zipTool = "/usr/bin/ditto"
    /// The CLI inside the Tailscale app, which matches the running daemon, then Homebrew's.
    static let cliPaths = [
        "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
        "/opt/homebrew/bin/tailscale", "/usr/local/bin/tailscale",
    ]

    /// The devices that can receive files now, never empty.
    static func targets(_ system: TaildropSystem) async throws -> [TaildropTarget] {
        guard let cli = system.cli() else { throw TaildropFailure.notInstalled }
        let listing = try await system.run(cli, ["file", "cp", "--targets"])
        guard listing.status == 0 else {
            let status = try await system.run(cli, ["status", "--json"])
            throw TaildropFailure.listing(status: status.output, errors: listing.errors)
        }
        let targets = TaildropTarget.parse(listing.output)
        guard !targets.isEmpty else { throw TaildropFailure.noDevices }
        return targets
    }

    /// Sends the Finder selection one item at a time; returns how many items went.
    static func send(
        to slug: String, system: TaildropSystem, progress: @MainActor @Sendable (_ done: Int, _ total: Int) -> Void
    ) async throws -> Int {
        guard let target = try await targets(system).first(where: { $0.slug == slug }) else {
            throw TaildropFailure.deviceGone
        }
        guard target.isOnline else { throw TaildropFailure.deviceOffline(target.name) }
        guard let cli = system.cli() else { throw TaildropFailure.notInstalled }
        let items = try await system.finderSelection().compactMap { raw -> (path: String, isFolder: Bool)? in
            guard let path = TaildropPlan.localPath(raw), let isFolder = system.isFolder(path) else { return nil }
            return (path, isFolder)
        }
        guard !items.isEmpty else { throw TaildropFailure.nothingSelected }
        let scratch = try system.makeScratch()
        defer { system.remove(scratch) }
        let uploads = TaildropPlan.uploads(items, scratch: scratch)
        for (done, upload) in uploads.enumerated() {
            try Task.checkCancellation()
            await progress(done, uploads.count)
            if let archive = upload.archive {
                let zipped = try await system.run(zipTool, ["-c", "-k", "--keepParent", upload.source, archive])
                guard zipped.status == 0 else {
                    throw TaildropFailure.zipFailed(URL(filePath: upload.source).lastPathComponent)
                }
            }
            let sent = try await system.run(cli, ["file", "cp", upload.file, target.address + ":"])
            guard sent.status == 0 else { throw TaildropFailure.refused(TaildropFailure.lastLine(sent.errors)) }
        }
        return uploads.count
    }
}
