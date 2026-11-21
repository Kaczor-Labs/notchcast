import Foundation

extension DownloadToolLookup: DownloadToolHost {
    func capture(_ executable: URL, arguments: [String], limit: Int) async throws -> (status: Int32, data: Data) {
        try await ChildProcess(
            executable: executable, arguments: arguments, environment: environment, reaper: children)
            .capture(limit: limit)
    }

    func run(
        _ executable: URL, arguments: [String], workingDirectory: URL?,
        onLine: @escaping @Sendable (String) -> Void
    ) async throws -> DownloadProcessResult {
        try await ChildProcess(
            executable: executable, arguments: arguments, environment: environment,
            workingDirectory: workingDirectory, reaper: children).run(onLine: onLine)
    }
}
