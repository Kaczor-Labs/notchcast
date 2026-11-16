// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadJob.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadProgress.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadState.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadTool.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/ChildProcess.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadQueue.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadRunContext.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadRunner.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadToolLookup.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadToolLookup+Host.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadsActivity.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadsIslandPolicy.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadsQueueController.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadsIslandBridge.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
import Foundation

/// Pins the island result: a finished batch leaves a checkmark notice, a failed job a plain failure notice.
@main
@MainActor
struct DownloadsResultTest {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "nc-downloads-result-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let webpage = try await run(root, kind: "webpage", sources: ["https://example.com/a"])
        expect(webpage.sawProgress, "a running job shows progress first")
        let saved = webpage.notices.last { $0.id == "dl.progress.saved" }
        expect(saved?.symbol == "checkmark.circle" && saved?.text == "Saved a.html" && saved?.isFailure == false,
               "a finished webpage leaves a checkmark and its file name: \(String(describing: saved))")
        expect(webpage.log.last == "post dl.progress.saved", "the result is posted after the progress ends")

        let failed = try await run(root, kind: "webpage", sources: ["fail"])
        let notice = failed.notices.first { $0.id.hasPrefix("dl.progress.failed.") }
        expect(notice?.isFailure == true && notice?.dwell == 4,
               "a failed job posts a failure notice with no dwell override (4 s)")
        expect(!failed.notices.contains { $0.id == "dl.progress.saved" }, "a failed job reports no success")

        let batch = try await run(root, kind: "webpage", sources: ["https://example.com/a", "https://example.com/b"])
        expect(batch.notices.filter { $0.id == "dl.progress.saved" }.map(\.text) == ["Saved 2 items"],
               "a batch of two reports one success")

        for kind in ["media", "transcript"] {
            let other = try await run(root, kind: kind, sources: ["https://example.com/a"])
            expect(other.notices.last { $0.id == "dl.progress.saved" }?.text == "Saved a.html",
                   "\(kind) jobs end with the same result")
        }
        let cancelled = try await interrupt(root) { controller in
            controller.queue!.cancel(controller.queue!.jobs[0].id)
        }
        let cancel = cancelled.notices.last { $0.id == "dl.progress.cancelled" }
        expect(cancel?.text == "Cancelled" && cancel?.symbol == "xmark.circle" && cancel?.isFailure == false,
               "cancelling the last running job leaves a plain Cancelled notice: \(String(describing: cancel))")
        expect(!cancelled.notices.contains { $0.id == "dl.progress.saved" }, "a cancelled job is not reported saved")

        let stopped = try await interrupt(root) { $0.stop() }
        let stop = stopped.notices.last { $0.id == "dl.progress.stopped" }
        expect(stop?.text == "Stopped" && stop?.isFailure == false, "switching off mid-download says Stopped")
        expect(stopped.log.suffix(2) == ["end dl.progress", "post dl.progress.stopped"],
               "the notice follows the end of the progress: \(stopped.log)")

        print("Downloads result: checkmark after a finished batch, plain failure notice, one success per batch")
    }

    private static func run(_ root: URL, kind: String, sources: [String]) async throws -> Capture {
        let presenter = Capture()
        let controller = DownloadsQueueController(
            file: root.appending(path: "q-\(UUID().uuidString).json"), destination: root,
            tools: DownloadToolLookup(directories: [], home: root, environment: [:]), report: { _ in })
        DownloadsIslandBridge.track(controller, presenter: presenter, noticeID: "dl.progress", symbol: "arrow.down.circle")
        let gate = Gate()
        controller.start { $0.register(FakeRunner(kind: kind, gate: gate)) }
        try await eventually { controller.queue != nil }
        _ = controller.accept(kind: kind, sources: sources)
        try await eventually { presenter.sawProgress }
        await gate.open()
        try await eventually { controller.queue?.jobs.allSatisfy { $0.state.isFinished } == true }
        try await Task.sleep(for: .milliseconds(100))
        controller.stop()
        return presenter
    }

    /// Starts one job, waits for its progress to show, then lets `action` end it before any result.
    private static func interrupt(
        _ root: URL, _ action: (DownloadsQueueController) -> Void
    ) async throws -> Capture {
        let presenter = Capture()
        let controller = DownloadsQueueController(
            file: root.appending(path: "q-\(UUID().uuidString).json"), destination: root,
            tools: DownloadToolLookup(directories: [], home: root, environment: [:]), report: { _ in })
        DownloadsIslandBridge.track(controller, presenter: presenter, noticeID: "dl.progress", symbol: "arrow.down.circle")
        controller.start { $0.register(FakeRunner(kind: "webpage", gate: Gate())) }
        try await eventually { controller.queue != nil }
        _ = controller.accept(kind: "webpage", sources: ["https://example.com/a"])
        try await eventually { presenter.sawProgress }
        action(controller)
        try await Task.sleep(for: .milliseconds(100))
        controller.stop()
        return presenter
    }

    private static func expect(_ value: Bool, _ message: String) { precondition(value, message) }

    private static func eventually(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !condition() {
            precondition(ContinuousClock.now < deadline, "timed out")
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private actor Gate {
        var isOpen = false
        func open() { isOpen = true }
    }

    private struct FakeRunner: DownloadRunner {
        let kind: String
        let gate: Gate
        var tools: [DownloadTool] = []

        func run(_ job: DownloadJob, context: DownloadRunContext) async throws -> URL? {
            while await !gate.isOpen { try await Task.sleep(for: .milliseconds(5)) }
            if job.source == "fail" { throw URLError(.cannotFindHost) }
            return context.destination.appending(path: URL(string: job.source)!.lastPathComponent + ".html")
        }
    }

    @MainActor private final class Capture: IslandPresenting {
        var notices: [IslandNotice] = []
        var log: [String] = []
        var sawProgress: Bool { notices.contains { $0.progress != nil } }

        func showLevel(_ level: IslandLevel) {}
        func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) {
            notices.append(notice)
            log.append("post \(notice.id)")
        }
        func end(notice id: String) { log.append("end \(id)") }
        func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {}
        func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
    }
}
