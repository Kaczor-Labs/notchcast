// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/TorrentBencode.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/TorrentMetainfo.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/TorrentInput.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/TorrentJob.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/TorrentStatus.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/TorrentJobPolicy.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/Aria2Arguments.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/TorrentSession.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/TorrentManager.swift
import Foundation
import Synchronization

/// The manager against a fake aria2c session and a hand-moved clock: no process, network or real time.
@main
@MainActor
struct TorrentManagerTest {
    static let hash = "c12fe1c06bba254a9dc9f519b335aa7c1367a88a"
    static let magnet = "magnet:?xt=urn:btih:\(hash)&dn=Big+Buck"
    nonisolated static let torrent = Data(("d8:announce1:a4:infod6:lengthi5e4:name5:a.txt12:piece lengthi16384e6:pieces20:"
        + String(repeating: "x", count: 20) + "ee").utf8)
    static let downloads = URL(filePath: "/srv/me/Downloads", directoryHint: .isDirectory)

    static func main() async {
        await refusals()
        await missingEngine()
        await lifecycle()
        await timeout()
        await engineDeath()
        print("Torrent manager: refusals, aria2c missing, duplicate, metadata follow, quarantine, cancel all, timeout")
    }

    final class Clock {
        var now = Date(timeIntervalSince1970: 1_000)
    }

    final class Recorder: @unchecked Sendable {
        let quarantined = Mutex<[URL]>([])
        let starts = Mutex(0)
    }

    static func make(_ fake: FakeSession?, clock: Clock, recorder: Recorder, keepSharing: Bool = false)
        -> TorrentManager {
        var environment = TorrentManager.Environment(downloads: downloads)
        environment.startSession = { extra in
            recorder.starts.withLock { $0 += 1 }
            expect(extra == ["--seam"], "extra arguments reach the session start")
            guard let fake else { throw TorrentEngineMissing() }
            return fake
        }
        environment.extraArguments = { ["--seam"] }
        environment.read = { input in
            guard case .file(let url) = input, url.lastPathComponent == "a.torrent" else { return Data("junk".utf8) }
            return torrent
        }
        environment.quarantine = { files in recorder.quarantined.withLock { $0 += files } }
        environment.sleep = { _ in throw CancellationError() }
        return TorrentManager(environment: environment, now: { clock.now }, keepSharing: { keepSharing })
    }

    private static func refusals() async {
        let manager = make(FakeSession(), clock: Clock(), recorder: Recorder())
        expect(await manager.submit([.magnet(magnet)]) == .notRunning, "switch off: the engine is not running")
        manager.start()
        expect(await manager.submit([]) == .nothingUsable, "nothing: nothing usable")
        expect(await manager.submit([.magnet("magnet:?xt=urn:btih:123"), .file(URL(filePath: "/x/b.torrent"))])
               == .nothingUsable, "a hashless magnet and a junk file are both refused")
        expect(manager.jobs.isEmpty, "a refused input queues nothing")
    }

    private static func missingEngine() async {
        let recorder = Recorder()
        let manager = make(nil, clock: Clock(), recorder: recorder)
        manager.start()
        expect(await manager.submit([.magnet(magnet)]) == .queued, "a valid magnet is queued")
        expect(manager.jobs.map(\.state) == [.failed("aria2c not found")], "no aria2c: the job fails saying so")
        expect(!manager.hasActiveJobs && manager.stopping == nil, "nothing is left to stop")
    }

    private static func lifecycle() async {
        let fake = FakeSession()
        let clock = Clock()
        let recorder = Recorder()
        let manager = make(fake, clock: clock, recorder: recorder)
        manager.start()
        expect(await manager.submit([.magnet(magnet), .file(URL(filePath: "/x/a.torrent"))]) == .queued, "queued")
        expect(recorder.starts.withLock { $0 } == 1, "one aria2c for every job")
        expect(fake.added == [.magnet(magnet), .torrent(torrent)], "a magnet by link, a file by its checked bytes")
        expect(fake.options.allSatisfy { $0 == ["seed-time": "0"] }, "without keep-sharing seeding stops at once")
        expect(manager.jobs.map(\.name) == ["Big Buck", "a.txt"], "named by dn and by info")
        expect(manager.jobs.map(\.state) == [.findingPeers, .findingPeers], "both look for peers")

        expect(await manager.submit([.magnet("magnet:?xt=urn:btih:\(hash.uppercased())&dn=Other")]) == .queued,
               "the same hash in upper case and another name is still the same torrent")
        expect(manager.jobs.last?.state == .failed("This torrent is already running."), "the copy fails as running")
        expect(fake.added.count == 2, "the copy never reaches aria2c")

        let magnetJob = manager.jobs[0]
        fake.statuses["g1"] = TorrentStatus(status: "complete", followedBy: ["g9"])
        fake.statuses["g2"] = TorrentStatus(status: "active", completed: 1, total: 5, speed: 1, connections: 2)
        await manager.poll()
        expect(manager.jobs[0].gid == "g9", "the metadata job hands over to the real download")
        expect(manager.jobs[1].state == .downloading, "the file job downloads")
        await settle()
        expect(fake.removed == ["g1"], "the metadata result is cleared")

        fake.statuses["g9"] = TorrentStatus(status: "active", completed: 5, total: 5, isSeeding: true,
                                            files: ["/srv/me/Downloads/Big Buck/a.mkv", "/etc/passwd"])
        await manager.poll()
        expect(recorder.quarantined.withLock { $0 } == [URL(filePath: "/srv/me/Downloads/Big Buck/a.mkv")],
               "finished files inside Downloads get the quarantine attribute")
        fake.statuses["g9"] = TorrentStatus(status: "complete", completed: 5, total: 5)
        await manager.poll()
        expect(manager.jobs[0].state == .finished, "aria2c's complete: finished")
        expect(recorder.quarantined.withLock { $0 }.count == 1, "quarantined once")

        manager.cancelAll()
        expect(manager.jobs[1].state == .cancelled && !manager.hasActiveJobs, "Cancel All stops every running job")
        await manager.stopping?.value
        expect(fake.stopCount == 1, "with no job left aria2c is stopped")

        expect(await manager.retry(manager.jobs[1].id) == .queued, "Try Again queues the same input")
        expect(recorder.starts.withLock { $0 } == 2 && manager.jobs.last?.name == "a.txt", "on a fresh aria2c")
        manager.dismiss(magnetJob.id)
        expect(!manager.jobs.contains { $0.id == magnetJob.id }, "Dismiss drops a finished row")
        let running = manager.jobs.last!.id
        manager.dismiss(running)
        expect(manager.jobs.contains { $0.id == running }, "a running row cannot be dismissed")

        manager.stop()
        expect(manager.jobs.allSatisfy { !$0.state.isActive }, "switching off cancels every job")
        await manager.stopping?.value
        expect(fake.stopCount == 2, "and stops aria2c")
        expect(await manager.submit([.magnet(magnet)]) == .notRunning, "and refuses new input")
    }

    private static func timeout() async {
        let fake = FakeSession()
        let clock = Clock()
        let manager = make(fake, clock: clock, recorder: Recorder())
        manager.start()
        await manager.submit([.magnet(magnet)])
        fake.statuses["g1"] = TorrentStatus(status: "active", total: 100)
        clock.now += 599
        await manager.poll()
        expect(manager.jobs[0].state == .findingPeers, "nine quiet minutes: still looking")
        clock.now += 1
        await manager.poll()
        expect(manager.jobs[0].state == .failed("No peers found in 10 minutes."), "ten: failed")
        await manager.stopping?.value
        await settle()
        expect(fake.removed == ["g1"] && fake.stopCount == 1, "the job is removed and aria2c stopped")
    }

    private static func engineDeath() async {
        let fake = FakeSession()
        let manager = make(fake, clock: Clock(), recorder: Recorder())
        manager.start()
        await manager.submit([.magnet(magnet)])
        fake.alive = false
        await manager.poll()
        expect(manager.jobs[0].state == .failed("aria2c stopped."), "a dead aria2c fails its jobs")
    }

    /// Lets the fire-and-forget removes run; the fake answers at once, so a few turns suffice.
    private static func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    static func expect(_ condition: Bool, _ message: String) {
        guard !condition else { return }
        print("FAIL: \(message)")
        exit(1)
    }
}

final class FakeSession: TorrentSession, @unchecked Sendable {
    private struct State {
        var added: [TorrentSource] = []
        var options: [[String: String]] = []
        var statuses: [String: TorrentStatus] = [:]
        var removed: [String] = []
        var stopCount = 0
        var alive = true
    }

    private let state = Mutex(State())

    var added: [TorrentSource] { state.withLock { $0.added } }
    var options: [[String: String]] { state.withLock { $0.options } }
    var removed: [String] { state.withLock { $0.removed } }
    var stopCount: Int { state.withLock { $0.stopCount } }
    var statuses: [String: TorrentStatus] {
        get { state.withLock { $0.statuses } }
        set { state.withLock { $0.statuses = newValue } }
    }
    var alive: Bool {
        get { state.withLock { $0.alive } }
        set { state.withLock { $0.alive = newValue } }
    }

    var isAlive: Bool { alive }

    func add(_ source: TorrentSource, options: [String: String]) async throws -> String {
        state.withLock {
            $0.added.append(source)
            $0.options.append(options)
            return "g\($0.added.count)"
        }
    }

    func status(_ gid: String) async throws -> TorrentStatus {
        guard let status = statuses[gid] else { throw Aria2Failure(message: "GID \(gid) is not found") }
        return status
    }

    func remove(_ gid: String) async { state.withLock { $0.removed.append(gid) } }

    func stop() async { state.withLock { $0.stopCount += 1 } }
}
