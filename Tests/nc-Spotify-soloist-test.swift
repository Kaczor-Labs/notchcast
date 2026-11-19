// notchcast-sources: Tinycast/Features/Notchcast/Spotify/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Spotify/Service/SoloistProcess.swift
// notchcast-sources: Tinycast/Features/Notchcast/Spotify/Service/SoloistHost.swift
// notchcast-sources: Tinycast/Features/Notchcast/Spotify/Service/SoloistInstaller.swift
// notchcast-sources: Tinycast/Features/Notchcast/Spotify/Service/SpotifySystem.swift

import Darwin
import Foundation
import Synchronization

func check(_ condition: Bool, _ message: String) {
    guard condition else { fatalError("nc-Spotify-soloist-test: \(message)") }
}

/// Stands in for signatures, processes and the clock; no Soloist ever runs.
final class FakeHost: Sendable {
    struct State {
        var signed = true
        var runningSigned = true
        var paths: [pid_t: String] = [:]
        var alive: Set<pid_t> = []
        var log: [String] = []
        var signals: [String] = []
        var line: (@Sendable (String) -> Void)?
        var ended: (@Sendable (SoloistExit) -> Void)?
    }

    let state = Mutex(State())
    func with<T: Sendable>(_ body: (inout sending State) -> sending T) -> T { state.withLock(body) }

    var host: SoloistHost {
        SoloistHost(
            verify: { url in self.with { $0.log.append("verify \(url.lastPathComponent)"); return $0.signed } },
            verifyRunning: { pid in self.with { $0.log.append("verifyRunning \(pid)"); return $0.runningSigned } },
            executablePath: { pid in self.with { $0.paths[pid] } },
            alive: { pid in self.with { $0.alive.contains(pid) } },
            signal: { pid, signal in
                self.with { state in
                    state.signals.append("\(pid) \(signal == SIGTERM ? "TERM" : signal == SIGKILL ? "KILL" : "?")")
                    return state.alive.contains(pid)
                }
            },
            now: { Date(timeIntervalSince1970: 0) },
            tick: {
                await Task.yield()
                try Task.checkCancellation()
            },
            spawn: { executable, arguments, line, ended in
                self.with { state in
                    state.log.append("spawn \(executable.lastPathComponent) \(arguments.contains("--api-key"))")
                    state.alive.insert(500)
                    state.line = line
                    state.ended = ended
                }
                return 500
            })
    }
}

/// Turns the main actor until `done`; the fake tick only yields, so this needs no real time.
@MainActor
func settle(until done: () -> Bool = { false }) async {
    for _ in 0..<10_000 where !done() { await Task.yield() }
}

func scratchPaths() -> SoloistPaths {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "nc-spotify-soloist-\(UUID().uuidString)", directoryHint: .isDirectory)
    let data = root.appending(path: "data", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
    return SoloistPaths(executable: root.appending(path: "soloist"), data: data)
}

func write(_ text: String, _ name: String, in paths: SoloistPaths) {
    try? text.write(to: paths.data.appending(path: name), atomically: true, encoding: .utf8)
}

@main
struct SoloistTests {
    @MainActor
    static func main() async {
        await verifiesBeforeEveryLaunch()
        await adoptsOnlyOurOwn()
        await ownsThePidFromSpawn()
        await installVerifiesWhatRuns()
        print("Soloist: verified before launch, adopts only its own, owns the pid, installs verified bytes")
    }

    @MainActor
    static func verifiesBeforeEveryLaunch() async {
        let fake = FakeHost()
        let paths = scratchPaths()
        write("4321", "ws.port", in: paths)
        write("127.0.0.1", "ws.addr", in: paths)
        let url = try? await SoloistProcess.launch(paths, key: "K", host: fake.host, spawned: { _ in },
                                                   exited: { _ in }, rejected: {})
        check(url?.absoluteString == "ws://127.0.0.1:4321", "a verified file launches")
        check(fake.with { $0.log } == ["verify soloist", "spawn soloist true"], "the file is verified right before")
        fake.with { $0.signed = false; $0.log = [] }
        do {
            _ = try await SoloistProcess.launch(paths, key: "K", host: fake.host, spawned: { _ in },
                                                exited: { _ in }, rejected: {})
            check(false, "an unverified file must not launch")
        } catch {
            check(error as? SoloistLaunchError == .notInstalled, "it reads as not installed")
        }
        check(!fake.with { $0.log }.contains { $0.hasPrefix("spawn") }, "the key never reaches a replaced file")
    }

    @MainActor
    static func adoptsOnlyOurOwn() async {
        let fake = FakeHost()
        let paths = scratchPaths()
        let installed = paths.executable.resolvingSymlinksInPath().path
        write("77", "soloist.pid", in: paths)
        write("4321", "ws.port", in: paths)
        write("127.0.0.1", "ws.addr", in: paths)
        fake.with { $0.alive = [77]; $0.paths = [77: installed] }
        check(SoloistProcess.adoptable(paths, host: fake.host) == 77, "our own signed Soloist is adopted")
        fake.with { $0.paths[77] = "/tmp/elsewhere/soloist" }
        check(SoloistProcess.adoptable(paths, host: fake.host) == nil, "a look-alike elsewhere is not")
        fake.with { $0.paths[77] = installed; $0.runningSigned = false }
        check(SoloistProcess.adoptable(paths, host: fake.host) == nil, "nor one whose running code fails the check")
        fake.with { $0.runningSigned = true; $0.signed = false }
        check(SoloistProcess.adoptable(paths, host: fake.host) == nil, "nor one whose file fails it")
        fake.with { $0.signed = true }
        try? FileManager.default.removeItem(at: paths.data.appending(path: "ws.addr"))
        check(SoloistProcess.socketURL(paths, host: fake.host, after: nil) == nil, "a missing ws.addr is refused")
        write("0.0.0.0", "ws.addr", in: paths)
        check(SoloistProcess.socketURL(paths, host: fake.host, after: nil) == nil, "a non-loopback one too")
        write("127.0.0.1", "ws.addr", in: paths)
        var stop: (@MainActor () -> Void)?
        let url = try? await SoloistProcess.launch(paths, key: "K", host: fake.host, spawned: { stop = $0 },
                                                   exited: { _ in }, rejected: {})
        check(url != nil && stop != nil && !fake.with { $0.log }.contains { $0.hasPrefix("spawn") }, "adopted")
        stop?()
        check(fake.with { $0.signals } == ["77 TERM"], "stopping an adopted Soloist signals it at once")
        check(SoloistProcess.adoptable(paths, host: fake.host) == nil, "a Soloist being stopped is never adopted")
        fake.with { $0.alive = [] }
        await settle { !SoloistProcess.stopping.contains(77) }
    }

    @MainActor
    static func ownsThePidFromSpawn() async {
        let fake = FakeHost()
        let paths = scratchPaths()
        var stop: (@MainActor () -> Void)?
        var exits: [SoloistExit] = []
        var rejections = 0
        let launch = Task {
            try await SoloistProcess.launch(paths, key: "K", host: fake.host, spawned: { stop = $0 },
                                            exited: { exits.append($0) }, rejected: { rejections += 1 })
        }
        while stop == nil { await Task.yield() }
        check(fake.with { $0.signals }.isEmpty, "the stop arrives at spawn, before any socket")
        fake.with { $0.line }?("soloist: login failed")
        launch.cancel()
        let result = await launch.result
        check((try? result.get()) == nil, "a cancelled launch fails")
        check(fake.with { $0.signals } == ["500 TERM"], "and signals the Soloist it spawned")
        stop?()
        check(fake.with { $0.signals } == ["500 TERM"], "a second stop does not signal again")
        fake.with { $0.ended }?(.exited(0))
        await settle { fake.with { $0.signals.count } == 2 && rejections == 1 }
        check(rejections == 1, "a refused key is reported")
        check(exits.isEmpty, "an exit we asked for is not reported as a crash")
        check(fake.with { $0.signals } == ["500 TERM", "500 KILL"], "one that ignores SIGTERM is killed")
        fake.with { $0.alive = [] }
        await settle { !SoloistProcess.stopping.contains(500) }

        let slow = FakeHost()
        stop = nil
        do {
            _ = try await SoloistProcess.launch(scratchPaths(), key: "K", host: slow.host, spawned: { stop = $0 },
                                                exited: { _ in }, rejected: {})
            check(false, "no socket, no launch")
        } catch {
            check(error as? SoloistLaunchError == .noSocket && slow.with { $0.signals } == ["500 TERM"], "timed out")
        }
        slow.with { $0.alive = [] }
        await settle { !SoloistProcess.stopping.contains(500) }
    }

    @MainActor
    static func installVerifiesWhatRuns() async {
        let target = scratchPaths().executable
        let ran = Mutex<[String]>([])
        let check2 = SoloistCodeCheck(
            verify: { url in ran.withLock { $0.append("verify \(url.path)") }; return true },
            version: { url in
                ran.withLock { $0.append("version \(url.path)") }
                return SoloistBuild(versionOutput: "soloist 1.4 build 1 (20990301)")!
            })
        let candidate = FileManager.default.temporaryDirectory.appending(path: "nc-spotify-candidate-\(UUID())")
        try? Data("new".utf8).write(to: candidate)
        let build = try? await SoloistInstaller.place(candidate, at: target, now: Date(timeIntervalSince1970: 0),
                                                      check: check2)
        let steps = ran.withLock { $0 }
        let staged = steps.first?.dropFirst("verify ".count) ?? ""
        check(build?.version == "1.4", "a verified build installs")
        check(steps.count == 2 && steps[1] == "version \(staged)", "--version runs the very file that was verified")
        check(URL(filePath: String(staged)).deletingLastPathComponent() == target.deletingLastPathComponent(),
              "verified beside its final place, so the rename keeps the verified bytes")
        check((try? String(contentsOf: target, encoding: .utf8)) == "new", "and lands at the installed path")

        try? Data("bad".utf8).write(to: candidate)
        ran.withLock { $0 = [] }
        let refused = SoloistCodeCheck(verify: { _ in false }, version: { url in
            ran.withLock { $0.append("version \(url.path)") }
            return SoloistBuild(versionOutput: "soloist 1.4 build 1 (20990301)")!
        })
        do {
            _ = try await SoloistInstaller.place(candidate, at: target, now: Date(timeIntervalSince1970: 0), check: refused)
            check(false, "an unsigned build must not install")
        } catch {
            check(error == .signature, "the signature is named")
        }
        check(ran.withLock { $0 }.isEmpty, "an unverified file never runs")
        check((try? String(contentsOf: target, encoding: .utf8)) == "new", "the installed build is untouched")
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: target.deletingLastPathComponent().path))
        check(leftovers?.filter { $0.hasPrefix(".soloist-") }.isEmpty == true, "no staged file is left behind")
    }
}
