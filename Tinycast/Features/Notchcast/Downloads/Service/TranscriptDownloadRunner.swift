import Foundation

struct TranscriptDownloadRunner: DownloadRunner {
    static let kind = "transcript"
    var kind: String { Self.kind }
    var tools: [DownloadTool] { [.ytDlp] }
    var rateLimitPause = MediaArguments.rateLimitPause
    var transcribeAudio: (@Sendable (String, DownloadRunContext) async throws -> URL)?

    struct Captions: Sendable {
        let stem: String
        let text: String
    }

    @concurrent
    func run(_ job: DownloadJob, context: DownloadRunContext) async throws -> URL? {
        if let captions = try await captions(for: job.source, context: context) {
            try Task.checkCancellation()
            return try JobOutput.publish(Data(captions.text.utf8), in: context.destination,
                                         stem: captions.stem, suffix: ".txt")
        }
        if let transcribeAudio { return try await transcribeAudio(job.source, context) }
        throw MediaFailure(detail: String(localized: "This video has no captions.", table: "NotchcastDownloads"))
    }

    @concurrent
    func captions(
        for source: String, context: DownloadRunContext, timestamps: Bool = false
    ) async throws -> Captions? {
        guard let executable = context.tools.find(.ytDlp) else { throw DownloadToolMissing(tool: .ytDlp) }
        let staging = FileManager.default.temporaryDirectory.appending(path: ".captions-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: staging) }
        let metadata = try await context.spawn(
            executable: executable, arguments: MediaArguments.originalLanguage(source: source))
        let original = metadata.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let language = original.isEmpty || original == "NA" ? nil : original
        let passes = (language == nil ? [(false, nil)] : [(false, language), (false, nil)]) + [(true, language)]
        for (index, pass) in passes.enumerated() {
            let (automatic, tracks) = pass
            // Each pass gets its own folder, so a track the other pass wrote never counts as this one's.
            let folder = staging.appending(path: String(index))
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let arguments = MediaArguments.captions(source: source, destination: folder, automatic: automatic,
                                                    language: tracks)
            var result = try await fetch(arguments, executable, context, folder)
            if MediaArguments.retryCaptions(stderr: result.errors, wroteCaptions: try !captions(in: folder).isEmpty) {
                try await Task.sleep(for: rateLimitPause)
                result = try await fetch(arguments, executable, context, folder)
            }
            try Task.checkCancellation()
            let files = try captions(in: folder)
            if files.isEmpty, MediaArguments.isRateLimited(result.errors) {
                throw MediaFailure(detail: String(
                    localized: "YouTube throttled the caption download. Try again later.", table: "NotchcastDownloads"))
            }
            for file in files {
                let text = CaptionText.plainText(try String(contentsOf: file, encoding: .utf8),
                                                 automatic: automatic, timestamps: timestamps)
                guard !text.isEmpty else { continue }
                let name = file.deletingPathExtension().deletingPathExtension().lastPathComponent
                try Task.checkCancellation()
                return Captions(stem: name, text: text)
            }
        }
        return nil
    }

    // yt-dlp exits 1 when one track fails, even after it wrote another; that run still counts.
    private func fetch(_ arguments: [String], _ executable: URL, _ context: DownloadRunContext,
                       _ folder: URL) async throws -> DownloadProcessResult {
        do {
            return try await context.spawn(executable: executable, arguments: arguments)
        } catch let failure as DownloadProcessFailure
                    where MediaArguments.isRateLimited(failure.result.errors) || (try? captions(in: folder).isEmpty) == false {
            return failure.result
        }
    }

    private func captions(in folder: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { ["vtt", "srt"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
