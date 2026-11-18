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
    /// The Markdown folder as the job begins; nil keeps every output in the Distill folder only.
    var notes: @MainActor @Sendable () -> DistillNotes? = { nil }
    /// Read again before a dropped file is converted and before it is trashed, so a change in between stops it.
    var dropFolder: @MainActor @Sendable () -> URL? = { nil }
    var kind: String { Self.kind }
    // A web link needs no tool, so a media link reports a missing one when it runs.
    let tools: [DownloadTool] = []

    func run(_ job: DownloadJob, context: DownloadRunContext) async throws -> URL? {
        let notes = await notes()
        let times = await timestamps()
        if job.source.hasPrefix("/") {
            guard let notes else { throw DistillFailure.noFolder }
            let file = URL(filePath: job.source)
            let stamp = try job.options(DistillDrop.Stamp.self)
            return try await endingOnBusy {
                try await convert(file, stamp: stamp, notes: notes, times: times, context: context)
            }
        }
        guard let url = URL(string: job.source), YtDlpAudio.isMedia(url) else {
            let page = try await WebpageRunner().run(job, context: context)
            if let page, let notes { try await Self.copy(page, to: notes) }
            return page
        }
        return try await endingOnBusy {
            try await transcript(of: job.source, times: times, notes: notes, context: context)
        }
    }

    private func endingOnBusy(_ body: () async throws -> URL) async throws -> URL {
        do {
            return try await body()
        } catch DistillFailure.busy {
            await onBusy()
            throw DistillFailure.busy
        }
    }

    @concurrent
    private static func copy(_ page: URL, to notes: DistillNotes) async throws {
        _ = try notes.copy(page)
    }

    @concurrent
    private func transcript(
        of link: String, times: Bool, notes: DistillNotes?, context: DownloadRunContext
    ) async throws -> URL {
        try await context.withDistillAudio(link: link, workDirectory: workDirectory) { media, audio, work in
            let text = DistillTranscript.text(try await segments(of: audio, in: work, context: context), times: times)
            guard !text.isEmpty else { throw DistillFailure.empty }
            let stem = DistillTranscript.stem(channel: media.channel, title: media.title)
            let output = try JobOutput.publish(Data(text.utf8), in: context.destination, stem: stem, suffix: ".txt")
            _ = try notes?.write(title: media.title, source: link, stem: stem, body: text)
            return output
        }
    }

    /// The audio's text, chunk by chunk through core's transcribe, each chunk with its start time.
    @concurrent
    func segments(
        of audio: URL, in work: URL, context: DownloadRunContext
    ) async throws -> [DistillTranscript.Segment] {
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
        return segments
    }
}

enum DistillFailure: LocalizedError, Equatable {
    case busy, unavailable, unreadableAudio, empty, unsupported, unreadable, changed, noFolder
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
        case .unsupported: String(localized: "Distill cannot convert this file.", table: "NotchcastDownloads")
        case .unreadable: String(localized: "The file could not be read.", table: "NotchcastDownloads")
        case .changed: String(localized: "The file changed while Distill read it.", table: "NotchcastDownloads")
        case .noFolder: String(localized: "Choose a Markdown folder for Distill first.", table: "NotchcastDownloads")
        case .failed(let detail): detail
        }
    }
}
