import Foundation

/// Finds the user's own yt-dlp, ffmpeg and aria2c; nothing is ever installed for them.
struct DownloadToolLookup: Sendable {
    struct Reading: Sendable {
        let tool: DownloadTool
        let path: URL?
        let version: String?
    }

    let directories: [URL]
    let environment: [String: String]
    /// Shared by every copy, so the queue that owns this lookup can end the runs it started.
    let children = ChildProcessReaper()

    init(
        directories: [URL]? = nil,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment parent: [String: String] = ProcessInfo.processInfo.environment
    ) {
        let folders = directories ?? Self.searchDirectories(home: home, path: parent["PATH"] ?? "/usr/bin:/bin")
        self.directories = folders
        var environment = parent
        environment["PATH"] = folders.map(\.path).joined(separator: ":")
        environment["HOME"] = environment["HOME"] ?? home.path
        self.environment = environment
    }

    /// An app started from Finder gets a bare PATH, so Homebrew's folders are searched as well.
    static func searchDirectories(home: URL, path: String) -> [URL] {
        let paths = ["/opt/homebrew/bin", "/usr/local/bin", home.appending(path: ".local/bin").path]
            + path.split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }.map { URL(filePath: $0, directoryHint: .isDirectory) }
    }

    func find(_ tool: DownloadTool) -> URL? {
        guard !tool.name.isEmpty, !tool.name.contains("/"), tool.name != ".", tool.name != ".." else { return nil }
        return directories.lazy.map { $0.appending(path: tool.name) }
            .first {
                var directory = ObjCBool(false)
                return FileManager.default.fileExists(atPath: $0.path, isDirectory: &directory)
                    && !directory.boolValue && FileManager.default.isExecutableFile(atPath: $0.path)
            }
    }

    @concurrent
    func lookup(_ tool: DownloadTool, timeout: Duration = .seconds(5)) async throws -> Reading {
        try Task.checkCancellation()
        guard let path = find(tool) else { return Reading(tool: tool, path: nil, version: nil) }
        let version = try await withThrowingTaskGroup(of: String?.self) { group in
            group.addTask {
                let result = try await ChildProcess(
                    executable: path, arguments: tool.versionArguments, environment: environment,
                    reaper: children).run()
                let output = result.output.isEmpty ? result.errors : result.output
                return output.split(whereSeparator: \.isNewline).first.map(String.init)
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                return nil
            }
            defer { group.cancelAll() }
            return try await group.next().flatMap { $0 }
        }
        try Task.checkCancellation()
        return Reading(tool: tool, path: path, version: version)
    }
}
