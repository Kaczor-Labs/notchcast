import Foundation

struct MediaDownloadRunner: DownloadRunner {
    let format: MediaArguments.Format
    /// Read when a job begins, so one that waited in the queue follows the switch as it is then.
    var aria2Enabled: @MainActor @Sendable () -> Bool
    var kind: String { format.kind }
    var tools: [DownloadTool] { [.ytDlp, .ffmpeg] }

    @concurrent
    func run(_ job: DownloadJob, context: DownloadRunContext) async throws -> URL? {
        guard let executable = context.tools.find(.ytDlp) else { throw DownloadToolMissing(tool: .ytDlp) }
        guard context.tools.find(.ffmpeg) != nil else { throw DownloadToolMissing(tool: .ffmpeg) }
        try FileManager.default.createDirectory(at: context.destination, withIntermediateDirectories: true)
        let aria2 = await aria2Enabled() ? context.tools.find(.aria2c)?.path : nil
        try Task.checkCancellation()
        func attempt(aria2Path: String?, restart: Bool = false) async throws -> DownloadProcessResult {
            let (stream, continuation) = AsyncStream<MediaOutput.Progress>.makeStream()
            async let reporting: Void = Self.report(stream, context: context)
            defer { continuation.finish() }
            let result = try await context.spawn(executable: executable, arguments: MediaArguments.download(
                source: job.source, destination: context.destination, format: format,
                aria2Path: aria2Path, restart: restart), onLine: { line in
                    guard let value = MediaOutput.progress(line) else { return }
                    continuation.yield(value)
                })
            continuation.finish()
            await reporting
            return result
        }
        let result: DownloadProcessResult
        do {
            result = try await attempt(aria2Path: aria2)
        } catch let failure as DownloadProcessFailure {
            try Task.checkCancellation()
            guard MediaArguments.retryNatively(stderr: failure.result.errors,
                                               source: job.source, usedAria2: aria2 != nil) else { throw failure }
            result = try await attempt(aria2Path: nil, restart: true)
        }
        try Task.checkCancellation()
        guard let output = result.output.split(whereSeparator: \.isNewline).reversed()
            .compactMap({ MediaOutput.outputPath(String($0), destination: context.destination) }).first,
            FileManager.default.fileExists(atPath: output.path) else {
            throw MediaFailure(detail: String(
                localized: "The downloader did not return an output file.", table: "NotchcastDownloads"))
        }
        return output
    }

    private static func report(_ stream: AsyncStream<MediaOutput.Progress>, context: DownloadRunContext) async {
        for await value in stream {
            guard !Task.isCancelled else { return }
            await context.report(DownloadProgress(
                fraction: value.fraction, received: value.received, total: value.total,
                bytesPerSecond: value.bytesPerSecond, eta: value.eta))
        }
    }
}
