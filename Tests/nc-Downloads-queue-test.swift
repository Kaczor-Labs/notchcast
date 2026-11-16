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
import Foundation

/// Pins the job queue: FIFO under a cap, actions, the seven-day expiry and the queue that survives a relaunch.
@main
struct DownloadsQueueTest {
    @MainActor
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "nc-downloads-queue-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let tools = DownloadToolLookup(directories: [], home: root, environment: [:])
        try await concurrencyAndFIFO(root, tools)
        try await actions(root, tools)
        try await relaunch(root, tools)
        try await persistence(root, tools)
        try await readOnlyJobs(root, tools)
        try await unreadablePersistence(root, tools)
        try await failedPersistence(root, tools)
        print("Downloads queue: FIFO under the cap, actions, expiry, and the queue survives a relaunch")
    }

    @MainActor
    private static func concurrencyAndFIFO(_ root: URL, _ tools: DownloadToolLookup) async throws {
        let probe = Probe()
        let queue = try await DownloadQueue(file: nil, destination: root, tools: tools)
        queue.register(GateRunner(probe: probe))
        let jobs = queue.enqueue(kind: "fake", sources: (0..<7).map(String.init))
        try await eventually { probe.started.count == 3 }
        expect(Set(probe.started) == Set(["0", "1", "2"]), "first three jobs start")
        expect(queue.jobs.filter { $0.state == .running }.count == 3, "default concurrency is three")
        expect(queue.jobs.suffix(4).allSatisfy { $0.state == .waiting }, "remaining jobs wait")
        probe.released.insert("0")
        try await eventually { probe.started.count == 4 }
        expect(probe.started.last == "3", "oldest waiting job starts next")
        probe.released.formUnion((0..<7).map(String.init))
        try await eventually { queue.jobs.allSatisfy { $0.state == .done } }
        expect(probe.maximum == 3, "runner concurrency never exceeds cap")
        expect(queue.jobs.map(\.id) == jobs.map(\.id), "rows stay ordered newest last")
        expect(queue.jobs.allSatisfy { $0.output?.hasPrefix(root.path) == true }, "runner output retained")
        await queue.stop()

        let serialProbe = Probe()
        let serial = try await DownloadQueue(file: nil, destination: root, maxConcurrent: 1, tools: tools)
        serial.register(GateRunner(probe: serialProbe))
        let unknown = serial.enqueue(kind: "unregistered", sources: ["unknown"])[0]
        expect(serial.jobs.first?.state == .failed && serial.jobs.first?.detail != nil,
               "unregistered runner fails without blocking FIFO")
        serial.enqueue(kind: "fake", sources: ["a", "b", "c", "d"])
        for (index, source) in ["a", "b", "c", "d"].enumerated() {
            try await eventually { serialProbe.started.count == index + 1 }
            expect(serialProbe.started.last == source, "FIFO start order")
            serialProbe.released.insert(source)
        }
        try await eventually { serial.jobs.filter { $0.id != unknown.id }.allSatisfy { $0.state == .done } }
        await serial.stop()
    }

    @MainActor
    private static func actions(_ root: URL, _ tools: DownloadToolLookup) async throws {
        let probe = Probe()
        let queue = try await DownloadQueue(file: nil, destination: root, maxConcurrent: 1, tools: tools)
        queue.register(GateRunner(probe: probe))
        let added = queue.enqueue(kind: "fake", sources: ["first", "second", "third"],
                                  options: Data(#"{"format":"mp3"}"#.utf8), group: "batch")
        try await eventually { probe.started.count == 1 }
        queue.cancel(added[1].id)
        expect(queue.jobs[1].state == .cancelled, "cancel waiting job")
        queue.cancel(added[0].id)
        queue.retry(added[0].id)
        expect(queue.jobs.last?.id == added[0].id, "retry moves same id to FIFO tail")
        expect(queue.jobs.last?.encodedOptions == added[0].encodedOptions && added[0].encodedOptions != nil
            && queue.jobs.last?.group == "batch", "retry retains input")
        try await eventually { probe.started.contains("third") }
        expect(!probe.started.contains("second"), "cancelled waiting runner never starts")
        probe.released.formUnion(["first", "third"])
        try await eventually { queue.jobs.filter { $0.state == .done }.count == 2 }
        expect(queue.jobs.last?.source == "first", "retry retains source")
        expect(queue.jobs.last?.progress?.fraction == 0.5, "runner progress applied")

        let held = queue.enqueue(kind: "fake", sources: ["held"], held: true)[0]
        try await Task.sleep(for: .milliseconds(30))
        expect(queue.jobs.last?.state == .held && !probe.started.contains("held"), "a held job waits for release")
        probe.released.insert("held")
        queue.release("fake")
        try await eventually { queue.jobs.first { $0.id == held.id }?.state == .done }
        await queue.stop()
    }

    /// #648: what was queued at quit is still queued at the next launch; only a cut-off run is lost.
    @MainActor
    private static func relaunch(_ root: URL, _ tools: DownloadToolLookup) async throws {
        let file = root.appending(path: "relaunch/queues/downloads.json")
        let probe = Probe()
        let first = try await DownloadQueue(file: file, destination: root, maxConcurrent: 1, tools: tools)
        first.register(GateRunner(probe: probe))
        let running = first.enqueue(kind: "fake", sources: ["running"])[0]
        let waiting = first.enqueue(kind: "fake", sources: ["waiting"], group: "batch")[0]
        let held = first.enqueue(kind: "fake", sources: ["held"], held: true)[0]
        try await eventually { probe.started == ["running"] }
        let stopping = first.halt()
        expect(first.jobs.first { $0.id == running.id }?.state == .interrupted, "halt marks the run interrupted at once")
        for task in stopping { await task.value }
        try await first.flush()

        let second = try await DownloadQueue(file: file, destination: root, maxConcurrent: 1, tools: tools)
        expect(second.jobs.map(\.id) == [running.id, waiting.id, held.id], "every row survives the relaunch in order")
        expect(second.jobs.map(\.state) == [.interrupted, .waiting, .held], "states survive; a cut-off run is interrupted")
        expect(second.jobs[1].group == "batch", "a waiting row keeps its input")
        let laterProbe = Probe()
        laterProbe.released = ["waiting"]
        second.register(GateRunner(probe: laterProbe))
        try await eventually { second.jobs[1].state == .done }
        expect(laterProbe.started == ["waiting"], "only the waiting row resumes; interrupted and held stay put")
        await second.stop()
    }

    @MainActor
    private static func persistence(_ root: URL, _ tools: DownloadToolLookup) async throws {
        let file = root.appending(path: "storage/downloads.json")
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let states: [DownloadState] = [.running, .waiting, .done, .failed, .cancelled, .interrupted]
        var rows = states.enumerated().map { index, state in
            DownloadJob(id: UUID().uuidString, kind: "fake", source: "row-\(index)", title: "Title",
                        group: "batch", state: state, progress: DownloadProgress(fraction: 0.2),
                        detail: "status", created: now.addingTimeInterval(-9 * 86400),
                        finished: state.isFinished ? now.addingTimeInterval(-86400) : nil,
                        encodedOptions: Data(#"{"format":"test"}"#.utf8))
        }
        for state in [DownloadState.done, .failed, .cancelled, .interrupted] {
            var row = rows[2]
            row.id = UUID().uuidString
            row.state = state
            row.finished = now.addingTimeInterval(-7 * 86400)
            rows.append(row)
        }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(rows).write(to: file, options: .atomic)
        let queue = try await DownloadQueue(file: file, destination: root, tools: tools, clock: { now })
        expect(queue.jobs.count == 6, "seven-day terminal expiry")
        expect(queue.jobs[0].state == .interrupted && queue.jobs[0].finished == now, "running reload becomes interrupted")
        expect(queue.jobs[1].state == .waiting, "old waiting job survives expiry")
        queue.register(OtherRunner())
        expect(queue.jobs[1].state == .waiting, "restored job waits for its own runner")
        expect(queue.jobs[2].created == rows[2].created, "expiry uses finish date")
        try await queue.flush()
        let stored = try JSONDecoder().decode([DownloadJob].self, from: Data(contentsOf: file))
        expect(stored == queue.jobs, "recovery persisted atomically")
        queue.enqueue(kind: "later", sources: ["one", "two"], options: Data(#"{"setting":"value"}"#.utf8), group: "new")
        queue.cancel(queue.jobs.last?.id ?? "")
        try await queue.flush()
        let reloaded = try await DownloadQueue(file: file, destination: root, tools: tools, clock: { now })
        expect(reloaded.jobs == queue.jobs, "ordered writes retain latest snapshot")
        await queue.stop()
        await reloaded.stop()
        try await reloaded.flush()
        try Data("invalid".utf8).write(to: file)
        let recovered = try await DownloadQueue(file: file, destination: root, tools: tools)
        expect(recovered.jobs.isEmpty && recovered.persistenceError != nil, "corrupt queue recovers with error")
        try expect(Data(contentsOf: file.appendingPathExtension("bad")) == Data("invalid".utf8),
                   "corrupt file is preserved")
        await recovered.stop()
    }

    @MainActor
    private static func readOnlyJobs(_ root: URL, _ tools: DownloadToolLookup) async throws {
        let file = root.appending(path: "read-only/downloads.json")
        var now = Date(timeIntervalSince1970: 2_000_000_000)
        let queue = try await DownloadQueue(file: file, destination: root, tools: tools, clock: { now })
        queue.enqueue(kind: "unregistered", sources: ["expired"])
        try await queue.flush()
        let original = try Data(contentsOf: file)
        now = now.addingTimeInterval(8 * 86400)
        expect(queue.jobs.count == 1, "reading jobs does not expire rows")
        try await queue.flush()
        try expect(Data(contentsOf: file) == original, "reading jobs does not persist changes")
        queue.enqueue(kind: "unregistered", sources: ["expired"])
        now = now.addingTimeInterval(8 * 86400)
        queue.enqueue(kind: "unregistered", sources: ["fresh"])
        expect(queue.jobs.map(\.source) == ["fresh"], "enqueue expires old finished rows")
        await queue.stop()
    }

    @MainActor
    private static func unreadablePersistence(_ root: URL, _ tools: DownloadToolLookup) async throws {
        let file = root.appending(path: "unreadable/downloads.json")
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        let marker = file.appending(path: "preserved")
        try Data("fixture".utf8).write(to: marker)
        let queue = try await DownloadQueue(file: file, destination: root, tools: tools)
        expect(queue.jobs.isEmpty && queue.persistenceError != nil, "unreadable queue starts empty with error")
        try expect(Data(contentsOf: file.appendingPathExtension("bad").appending(path: "preserved"))
                   == Data("fixture".utf8), "unreadable queue is moved aside intact")
        queue.enqueue(kind: "unregistered", sources: ["new"])
        try await queue.flush()
        let rows = try JSONDecoder().decode([DownloadJob].self, from: Data(contentsOf: file))
        expect(rows.map(\.source) == ["new"], "recovered queue persists new jobs")
        await queue.stop()
    }

    @MainActor
    private static func failedPersistence(_ root: URL, _ tools: DownloadToolLookup) async throws {
        let parent = root.appending(path: "failed-write")
        let file = parent.appending(path: "downloads.json")
        let queue = try await DownloadQueue(file: file, destination: root, tools: tools)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.removeItem(at: parent)
        try Data("blocked".utf8).write(to: parent)
        queue.enqueue(kind: "unregistered", sources: ["fixture"])
        do {
            try await queue.flush()
            preconditionFailure("failed persistence must throw")
        } catch {
            expect(queue.persistenceError == error.localizedDescription, "write failure remains observable")
        }
        await queue.stop()
        expect(queue.persistenceError != nil, "stop retains flush failure")
    }

    private static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) rethrows {
        let held = try value()
        precondition(held, message)
    }

    @MainActor
    private static func eventually(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while !condition() {
            guard ContinuousClock.now < deadline else { throw HarnessError.timeout }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private enum HarnessError: Error { case timeout }

    @MainActor
    private final class Probe {
        var started: [String] = []
        var released = Set<String>()
        var active = 0
        var maximum = 0

        func begin(_ source: String) {
            started.append(source)
            active += 1
            maximum = max(maximum, active)
        }

        func end() { active -= 1 }
    }

    private struct OtherRunner: DownloadRunner {
        let kind = "other"
        var tools: [DownloadTool] = []

        func run(_ job: DownloadJob, context: DownloadRunContext) async throws -> URL? { nil }
    }

    private struct GateRunner: DownloadRunner {
        let kind = "fake"
        let probe: Probe
        var tools: [DownloadTool] = []

        func run(_ job: DownloadJob, context: DownloadRunContext) async throws -> URL? {
            await probe.begin(job.source)
            do {
                await context.report(DownloadProgress(fraction: 0.5, received: 5, total: 10))
                while await !probe.released.contains(job.source) { try await Task.sleep(for: .milliseconds(5)) }
                try Task.checkCancellation()
                await probe.end()
                return context.destination.appending(path: job.source)
            } catch {
                await probe.end()
                throw error
            }
        }
    }
}
