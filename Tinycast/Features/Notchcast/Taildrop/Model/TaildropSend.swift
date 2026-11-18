import Foundation

enum TaildropListing: Equatable, Sendable {
    case notInstalled
    case targets([TaildropTarget])
    /// Installed but gave no list: stopped, signed out or not answering.
    case unavailable
}

/// The two things asked of `tailscale`: who can receive, and to take the selection there.
enum TaildropSend {
    static let listSeconds: TimeInterval = 5

    static func targets(_ environment: TaildropEnvironment) async -> TaildropListing {
        guard let cli = environment.findCLI() else { return .notInstalled }
        let ask = TaildropInvocation(
            executable: cli, arguments: ["file", "cp", "--targets"], timeLimit: listSeconds)
        guard let reply = try? await environment.run(ask, { _ in }), reply.status == 0 else { return .unavailable }
        return .targets(TaildropTarget.parse(reply.output))
    }

    /// `progress` gets the share of bytes sent, or nil while a folder is being zipped.
    static func send(
        to target: TaildropTarget, environment: TaildropEnvironment,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws {
        let selection = try await environment.finderSelection()
        guard !selection.isEmpty else { throw TaildropFailure.nothingSelected }
        guard let cli = environment.findCLI() else { throw TaildropFailure.notInstalled }
        var scratch: [URL] = []
        defer { scratch.forEach(environment.remove) }
        var files: [(url: URL, bytes: Int64)] = []
        for item in selection {
            let name = item.lastPathComponent
            switch environment.inspect(item) {
            case nil:
                throw TaildropFailure.unreadable(name)
            case .file(let bytes):
                files.append((item, bytes))
            case .folder:
                // `tailscale file cp` refuses a folder ("directories not supported"), so it goes zipped.
                progress(nil)
                guard let folder = try? environment.makeScratch() else { throw TaildropFailure.zipFailed(name) }
                scratch.append(folder)
                let archive = folder.appending(path: name + ".zip")
                let zip = TaildropInvocation(executable: environment.zipTool, arguments: zipArguments(item, archive))
                guard try await environment.run(zip, { _ in }).status == 0,
                    case .file(let bytes) = environment.inspect(archive)
                else { throw TaildropFailure.zipFailed(name) }
                files.append((archive, bytes))
            }
        }
        let total = files.reduce(0) { $0 + $1.bytes }
        var sent: Int64 = 0
        for file in files {
            let before = sent
            let reply = try await environment.run(copy(file.url, to: target, cli: cli)) { read in
                progress(total > 0 ? min(1, Double(before + read) / Double(total)) : nil)
            }
            guard reply.status == 0 else { throw TaildropFailure(output: reply.output) }
            sent += file.bytes
        }
    }

    /// The file goes in on stdin: Tailscale's Mac app CLI is sandboxed and cannot open a path.
    static func copy(_ file: URL, to target: TaildropTarget, cli: URL) -> TaildropInvocation {
        TaildropInvocation(
            executable: cli, arguments: ["file", "cp", "--name=" + file.lastPathComponent, "-", target.destination],
            input: file)
    }

    /// `--keepParent` puts the folder itself in the archive, so it unpacks under its own name.
    static func zipArguments(_ folder: URL, _ archive: URL) -> [String] {
        ["-c", "-k", "--sequesterRsrc", "--keepParent", folder.path, archive.path]
    }
}
