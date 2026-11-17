import Foundation

/// Saves a link into the Distill folder: media as a transcript through core, any other link as a page.
nonisolated struct DistillRunner: DownloadRunner {
    typealias Transcribe = @MainActor @Sendable (URL) async throws -> String

    static let kind = "distill"
    // Fixed cuts can split a word; the core bridge already cuts each chunk again at its own pauses.
    static let chunkSeconds = 240
    let workDirectory: URL
    let transcribe: Transcribe
    /// Read when a job begins, so one that waited in the queue follows the switch as it is then.
    let timestamps: @MainActor @Sendable () -> Bool
    /// Busy ends the run, so the links still waiting go back on hold instead of each failing busy.
    let onBusy: @MainActor @Sendable () -> Void
    var kind: String { Self.kind }
    // A web link needs no tool, so a media link reports a missing one when it runs.
    let tools: [DownloadTool] = []

    func run(_ job: DownloadJob, context: DownloadRunContext) async throws -> URL? {
        guard let url = URL(string: job.source), YtDlpAudio.isMedia(url) else {
            return try await WebpageRunner().run(job, context: context)
        }
        let times = await timestamps()
        do {
            return try await transcript(of: job.source, times: times, context: context)
        } catch DistillFailure.busy {
            await onBusy()
            throw DistillFailure.busy
        }
    }

    @concurrent
    private func transcript(of link: String, times: Bool, context: DownloadRunContext) async throws -> URL {
        try await context.withDistillAudio(link: link, workDirectory: workDirectory) { media, audio, work in
            let chunks = try await context.distillChunks(of: audio, seconds: Self.chunkSeconds, in: work)
            var segments: [DistillTranscript.Segment] = []
            for (index, chunk) in chunks.enumerated() {
                try Task.checkCancellation()
                await context.report(DownloadProgress(
                    fraction: Double(index) / Double(chunks.count),
                    stage: String(localized: "Transcribing \(index + 1) of \(chunks.count)",
                                  table: "NotchcastDownloads")))
                let text: String
                do {
                    text = try await transcribe(chunk)
                } catch let error as NotchcastTranscribeError {
                    throw DistillFailure(error)
                }
                segments.append(.init(start: TimeInterval(index * Self.chunkSeconds), text: text))
            }
            try Task.checkCancellation()
            let text = DistillTranscript.text(segments, times: times)
            guard !text.isEmpty else { throw DistillFailure.empty }
            return try JobOutput.publish(Data(text.utf8), in: context.destination,
                                         stem: DistillTranscript.stem(channel: media.channel, title: media.title),
                                         suffix: ".txt")
        }
    }
}

enum DistillFailure: LocalizedError, Equatable {
    case busy, unavailable, unreadableAudio, empty
    case failed(String)

    init(_ error: NotchcastTranscribeError) {
        switch error {
        case .busy: self = .busy
        case .unavailable: self = .unavailable
        case .unreadableAudio: self = .unreadableAudio
        case .failed(let detail): self = .failed(detail)
        }
    }

    var errorDescription: String? {
        switch self {
        case .busy: String(localized: "Dictation is in use. Run Distill again when it is free.",
                           table: "NotchcastDownloads")
        case .unavailable: String(localized: "Dictation is not available. Set up a dictation model first.",
                                  table: "NotchcastDownloads")
        case .unreadableAudio: String(localized: "The audio could not be read.", table: "NotchcastDownloads")
        case .empty: String(localized: "No speech was found.", table: "NotchcastDownloads")
        case .failed(let detail): detail
        }
    }
}
