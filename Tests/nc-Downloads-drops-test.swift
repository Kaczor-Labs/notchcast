// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastTranscription.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DistillDrop.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DistillNote.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DistillTranscript.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadJob.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadProgress.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadState.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadTool.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadsWebRules.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/HTMLDocument.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/HTMLMarkdown.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/WebpageArticle.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/WebpageExtraction.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/YtDlpAudio.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DistillNotes.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DistillRunner.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadRunContext+Distill.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadRunContext.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadRunner.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/JobOutput.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/PublicWebAddress.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/PublicWebProxy.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/WebpageExtractor.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/WebpageRunner.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/WebpageSaver.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/WebpageWebViewConfiguration.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/XPost.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/ChildProcess.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DistillDropWatcher.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadQueue.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadToolLookup+Host.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadToolLookup.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadsQueueController.swift
// notchcast-sources: Tinycast/Features/FileSearch/Service/FileSystemWatcher.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
import Foundation
import Observation

/// The dropped-file watcher on a real folder: files already there when Convert goes on, or at launch, are
/// never queued; one that appears later is queued after it settles; a new folder cancels what was queued;
/// a folder that cannot be listed forgets nothing into "new"; a change that lands after stop starts
/// nothing. The stand-in runner parks each job and touches no file.
@main
@MainActor
struct DownloadsDropsTest {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "nc-downloads-drops-\(UUID().uuidString)", directoryHint: .isDirectory)
        let folder = root.appending(path: "Notes", directoryHint: .isDirectory)
        let other = root.appending(path: "Other", directoryHint: .isDirectory)
        for directory in [folder, other] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "nc-downloads-drops-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = Clock()
        let naps = Naps()
        let settle = DistillDrop.settle

        let kept = ["paper.pdf", "page.html", "talk.mp3", "clip.mov"]
        for name in kept { try Data("already here".utf8).write(to: folder.appending(path: name)) }
        defaults.set(folder.path(percentEncoded: false), forKey: DistillNotes.folderKey)

        let distill = try await queue(root, "switch")
        let watcher = DistillDropWatcher(defaults: defaults, now: { clock.now }, distill: distill,
                                         sleep: { try await naps.sleep($0) })
        watcher.start()
        _ = await looked(watcher)
        expect(watcher.folder == nil && sources(distill).isEmpty, "Convert off: no folder is watched")

        defaults.set(true, forKey: DistillNotes.convertKey)
        while watcher.folder == nil { await Task.yield() }
        _ = await looked(watcher)
        clock.now += settle * 3
        _ = await looked(watcher)
        let swept = await looked(watcher, retryFailed: true)
        expect(swept == 0 && sources(distill).isEmpty,
               "files in the folder before Convert went on are never queued, by a later look or by Run Distill: "
               + "\(sources(distill))")

        try Data("new".utf8).write(to: folder.appending(path: "new.pdf"))
        let first = await looked(watcher)
        expect(first == 0 && sources(distill).isEmpty, "a new file is only remembered at first")
        expect(naps.asked.last == settle, "the next look is set for when it settles: \(naps.asked)")
        clock.now += settle
        naps.wake()
        await until { !sources(distill).isEmpty }
        let job = distill.queue?.jobs.first
        expect(sources(distill) == ["new.pdf"], "only the file that appeared is queued: \(sources(distill))")
        try expect(job?.options(DistillDrop.Stamp.self) == DistillDrop.stamp(at: job?.source ?? "") && job?.encodedOptions != nil,
                   "its job carries the stamp it settled with")
        try expect(Set(FileManager.default.contentsOfDirectory(atPath: folder.path)) == Set(kept + ["new.pdf"]),
               "queueing touches no file")
        watcher.stop()
        distill.stop()

        try await launch(root, folder: folder, other: other, defaults: defaults, clock: clock, kept: kept + ["new.pdf"])
        print("Downloads drops: files already in the folder at switch-on and at launch stay; a later one is queued "
              + "once settled; a new folder cancels it; a change after stop starts nothing")
    }

    /// A fresh queue and watcher with Convert already on, as the app starts them.
    private static func launch(
        _ root: URL, folder: URL, other: URL, defaults: UserDefaults, clock: Clock, kept: [String]
    ) async throws {
        let settle = DistillDrop.settle
        let distill = try await queue(root, "launch")
        let naps = Naps()
        let watcher = DistillDropWatcher(defaults: defaults, now: { clock.now }, distill: distill,
                                         sleep: { try await naps.sleep($0) })
        watcher.start()
        expect(watcher.folder != nil, "launch with Convert on watches the folder at once")
        _ = await looked(watcher)
        clock.now += settle * 3
        _ = await looked(watcher)
        let swept = await looked(watcher, retryFailed: true)
        expect(swept == 0 && sources(distill).isEmpty,
               "files in the folder at launch are never queued: \(sources(distill))")

        let away = root.appending(path: "Away", directoryHint: .isDirectory)
        try FileManager.default.moveItem(at: folder, to: away)
        _ = await looked(watcher)
        try FileManager.default.moveItem(at: away, to: folder)
        _ = await looked(watcher)
        clock.now += settle * 3
        _ = await looked(watcher)
        expect(sources(distill).isEmpty,
               "a folder that could not be listed and came back holds no new file: \(sources(distill))")

        try Data("<p>late</p>".utf8).write(to: folder.appending(path: "late.htm"))
        _ = await looked(watcher)
        expect(sources(distill).isEmpty, "one look is not enough")
        clock.now += settle
        // The write's own file event may look first and queue it, so the count of one look proves nothing.
        _ = await looked(watcher)
        expect(sources(distill) == ["late.htm"], "the second look queues it")
        expect(distill.queue?.jobs.first?.state == .running, "its job is running")

        defaults.set(other.path(percentEncoded: false), forKey: DistillNotes.folderKey)
        while watcher.folder?.lastPathComponent != "Other" { await Task.yield() }
        expect(distill.queue?.jobs.first?.state == .cancelled, "a new folder cancels the job queued from the old one")
        try expect(Set(FileManager.default.contentsOfDirectory(atPath: folder.path)) == Set(kept + ["late.htm"]),
               "and every file stays where it was")

        defaults.set(folder.path(percentEncoded: false), forKey: DistillNotes.folderKey)
        watcher.stop()
        for _ in 0..<3 { await Task { @MainActor in }.value }
        expect(watcher.folder == nil, "a change that arrives after stop does not start the watch again")
        distill.stop()
    }

    private static func queue(_ root: URL, _ name: String) async throws -> DownloadsQueueController {
        let controller = DownloadsQueueController(
            file: root.appending(path: "\(name).json"), destination: root.appending(path: "Raw", directoryHint: .isDirectory),
            maxConcurrent: 1, tools: DownloadToolLookup(directories: [root.appending(path: "bin")], home: root),
            report: { preconditionFailure("the queue reported: \($0)") })
        controller.start { $0.register(Parked()) }
        await until { controller.queue != nil }
        return controller
    }

    /// One more look, after any look already under way.
    private static func looked(_ watcher: DistillDropWatcher, retryFailed: Bool = false) async -> Int {
        await withCheckedContinuation { continuation in
            watcher.rescan(retryFailed: retryFailed) { continuation.resume(returning: $0) }
        }
    }

    private static func sources(_ distill: DownloadsQueueController) -> [String] {
        distill.queue?.jobs.map { URL(filePath: $0.source).lastPathComponent } ?? []
    }

    /// Waits on Observation, never on time: a condition that never holds ends in the runner's timeout.
    private static func until(_ condition: @escaping @MainActor () -> Bool) async {
        while !condition() {
            await withCheckedContinuation { continuation in
                withObservationTracking { _ = condition() } onChange: { continuation.resume() }
            }
        }
    }

    private static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) rethrows {
        let held = try value()
        precondition(held, message)
    }
}

@MainActor
private final class Clock {
    var now = Date(timeIntervalSince1970: 1_000_000)
}

/// Stands in for the watcher's sleep: it records each wait and ends it only on `wake` or cancellation.
@MainActor
private final class Naps {
    private(set) var asked: [TimeInterval] = []
    private var waiting: [UUID: CheckedContinuation<Void, Never>] = [:]

    func sleep(_ delay: TimeInterval) async throws {
        asked.append(delay)
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { waiting[id] = $0 }
        } onCancel: {
            Task { @MainActor in self.waiting.removeValue(forKey: id)?.resume() }
        }
        try Task.checkCancellation()
    }

    func wake() {
        let sleepers = waiting.values
        waiting = [:]
        for sleeper in sleepers { sleeper.resume() }
    }
}

/// Holds each job running until it is cancelled, so nothing is converted and nothing is trashed.
private struct Parked: DownloadRunner {
    let kind = DistillRunner.kind
    let tools: [DownloadTool] = []

    func run(_ job: DownloadJob, context: DownloadRunContext) async throws -> URL? {
        let (stream, hold) = AsyncStream<Never>.makeStream()
        for await _ in stream {}
        withExtendedLifetime(hold) {}
        throw CancellationError()
    }
}
