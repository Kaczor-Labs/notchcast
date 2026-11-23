// notchcast-sources: Tinycast/Features/Notchcast/MacTweaks/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/MacTweaks/Service/*.swift
// notchcast-sources: Tinycast/Platform/AppPaths.swift Tinycast/Platform/ProcessExit.swift
import Foundation
import Synchronization

@MainActor
protocol NotchcastModule: AnyObject {
    func start()
    func stop()
}

@main
struct MacTweaksStoreTest {
    private enum FakeFailure: Error { case write }

    private final class FakeSystem: Sendable {
        struct State {
            var values: [MacTweakTarget: MacTweakValue] = [:]
            var managed: Set<MacTweakTarget> = []
            var elsewhere: [MacTweakTarget: MacTweakHeldElsewhere] = [:]
            var fallback: [MacTweakTarget: MacTweakValue] = [:]
            var reads = 0
            var readAlls = 0
            var refuseWrites: Set<MacTweakTarget> = []
            var writes: [MacTweakTarget] = []
            var restarts: [MacTweakRestart] = []
        }

        let state = Mutex(State())
        let folder: URL

        init(folder: URL) {
            self.folder = folder
        }

        var journalFile: URL { folder.appending(path: "journal.json") }

        func reading(_ target: MacTweakTarget) -> MacTweaksSystem.Reading {
            state.withLock { state in
                if state.values[target] == nil, let fallback = state.fallback[target] {
                    return MacTweaksSystem.Reading(stored: nil, effective: fallback, heldElsewhere: .everyApp)
                }
                return MacTweaksSystem.Reading(
                    stored: state.values[target],
                    effective: state.values[target],
                    managed: state.managed.contains(target),
                    heldElsewhere: state.elsewhere[target]
                )
            }
        }

        func make(beforeRestart: @escaping @Sendable () -> Void = {}) -> MacTweaksSystem {
            MacTweaksSystem(
                version: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0),
                journalFolder: folder,
                read: { target in
                    self.state.withLock { $0.reads += 1 }
                    return self.reading(target)
                },
                readAll: { targets in
                    self.state.withLock { $0.readAlls += 1 }
                    return Dictionary(targets.map { ($0, .success(self.reading($0))) }, uniquingKeysWith: { a, _ in a })
                },
                write: { target, value in
                    let journal = try MacTweakJournal.decode(Data(contentsOf: self.journalFile))
                    self.state.withLock { state in
                        let entry = journal.entries.first { $0.target == target.canonical }
                        precondition(entry != nil, "System write reached the seam without a journal entry")
                        precondition(entry?.written == value || entry?.previous == value)
                        precondition(!state.managed.contains(target) && state.elsewhere[target] == nil)
                    }
                    try self.state.withLock { state in
                        state.writes.append(target)
                        guard !state.refuseWrites.contains(target) else { throw FakeFailure.write }
                        state.values[target] = value
                    }
                },
                restart: { process in
                    beforeRestart()
                    self.state.withLock { $0.restarts.append(process) }
                },
                now: { Date(timeIntervalSince1970: 100) }
            )
        }
    }

    @MainActor
    static func main() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }

        let pathBar = MacTweakTarget.preference(domain: "com.example.finder", key: "PathBar")
        let statusBar = MacTweakTarget.preference(domain: "com.example.finder", key: "StatusBar")
        let locked = MacTweakTarget.preference(domain: "com.example.finder", key: "Locked")
        let inherited = MacTweakTarget.preference(domain: "com.example.finder", key: "Inherited")
        let service = MacTweakTarget.service(label: "com.example.media-keys")
        let start: [MacTweakTarget: MacTweakValue] = [pathBar: .string("NO"), service: .bool(false)]
        let fake = FakeSystem(folder: folder)
        fake.state.withLock {
            $0.values = start
            $0.managed = [locked]
            $0.elsewhere = [inherited: .thisMac]
        }
        let catalogue = [
            MacTweak(id: "path", group: .finder, changes: [.preference(pathBar, .bool(true))],
                     restarts: [.finder], presets: [.recommended]),
            MacTweak(id: "status", group: .finder, changes: [.preference(statusBar, .bool(true))],
                     restarts: [.finder], presets: [.recommended]),
            MacTweak(id: "locked", group: .finder, changes: [.preference(locked, .bool(true))]),
            MacTweak(id: "inherited", group: .finder, changes: [.preference(inherited, .bool(true))]),
            MacTweak(id: "media-keys", group: .annoyances, changes: [.service("com.example.media-keys")],
                     presets: [.maximumPrivacy]),
        ]

        let (started, signal) = AsyncStream.makeStream(of: Void.self)
        let release = DispatchSemaphore(value: 0)
        let reached = Mutex(false)
        let module = MacTweaksModule(catalogue: catalogue, system: fake.make(beforeRestart: {
            let first = reached.withLock { reached in
                defer { reached = true }
                return !reached
            }
            if first {
                signal.yield()
                release.wait()
            }
        }))
        module.start()
        let store = module.store
        var reachedRestart = started.makeAsyncIterator()
        let running = Task {
            defer { signal.finish() }
            return try await store.runPreset(.maximumPrivacy)
        }
        guard await reachedRestart.next() != nil else { preconditionFailure("Preset did not reach its restart") }
        precondition(store.isBusy)
        do {
            _ = try await store.undoEverything()
            preconditionFailure("Concurrent mutations must be refused")
        } catch MacTweaksStore.Failure.busy {}
        let readsBefore = fake.state.withLock { ($0.reads, $0.readAlls) }
        let during = try await store.snapshot()
        precondition(during.states["media-keys"] == .applied, "A snapshot reads while a batch restarts")
        precondition(fake.state.withLock { ($0.reads, $0.readAlls) } == (readsBefore.0, readsBefore.1 + 1),
                     "A snapshot reads every target in one pass")
        precondition(store.isBusy)
        release.signal()
        let applied = try await running.value
        precondition(applied.isEmpty)
        precondition(!store.isBusy)
        let after = try await store.snapshot()
        precondition(Set(after.states.filter { $0.value == .applied }.keys) == ["path", "status", "media-keys"])
        precondition(after.states["locked"] == .managed)
        precondition(after.states["inherited"] == .heldElsewhere(.thisMac))
        module.stop()

        let reopened = MacTweaksModule(catalogue: Array(catalogue.dropLast()), system: fake.make())
        reopened.start()
        let restoreStore = reopened.store
        let lockedResult = try await restoreStore.set("locked", on: true)
        let inheritedResult = try await restoreStore.set("inherited", on: true)
        guard case .blocked("locked", .managed)? = lockedResult.first,
              case .blocked("inherited", .heldElsewhere(.thisMac))? = inheritedResult.first
        else { preconditionFailure("Blocked keys must report why") }

        let rowRestored = try await restoreStore.set("path", on: false)
        precondition(rowRestored.isEmpty)
        fake.state.withLock {
            precondition($0.values[pathBar] == start[pathBar])
            precondition($0.restarts == [.finder, .finder])
            $0.restarts.removeAll()
        }
        let reapplied = try await restoreStore.runPreset(.recommended)
        precondition(reapplied.isEmpty)
        fake.state.withLock { $0.restarts.removeAll() }

        let undone = try await restoreStore.undoEverything()
        precondition(undone.isEmpty)
        fake.state.withLock {
            precondition($0.values[service] == .bool(true), "An entry the catalogue does not know is left alone")
            $0.values[service] = start[service]
            precondition($0.values == start)
            $0.values[service] = .bool(true)
            precondition($0.restarts == [.finder])
            precondition(!$0.writes.contains(locked) && !$0.writes.contains(inherited))
        }
        let kept = try MacTweakJournal.decode(Data(contentsOf: fake.journalFile))
        precondition(kept.entries.map(\.target) == [service], "An unknown entry stays in the journal")
        let fullUndo = try await MacTweaksStore(catalogue: catalogue, system: fake.make()).undoEverything()
        precondition(fullUndo.isEmpty)
        precondition(fake.state.withLock { $0.values } == start)

        let beforeFailure = try await restoreStore.runPreset(.recommended)
        precondition(beforeFailure.isEmpty)
        fake.state.withLock {
            $0.values[pathBar] = .integer(1)
            $0.refuseWrites.insert(statusBar)
        }
        let failed = try await restoreStore.undoEverything()
        guard case .change("status", statusBar, _)? = failed.first else {
            preconditionFailure("A failed restore must be reported")
        }
        let remaining = try MacTweakJournal.decode(Data(contentsOf: fake.journalFile))
        precondition(remaining.entries.map(\.target) == [statusBar])
        fake.state.withLock { $0.refuseWrites.removeAll() }
        let retried = try await restoreStore.undoEverything()
        precondition(retried.isEmpty)
        fake.state.withLock {
            precondition($0.values[pathBar] == .integer(1))
            precondition($0.values[statusBar] == nil)
        }

        _ = fake.state.withLock { $0.refuseWrites.insert(statusBar) }
        let refusedApply = try await restoreStore.set("status", on: true)
        guard case .change("status", statusBar, _)? = refusedApply.first else {
            preconditionFailure("A failed apply must be reported")
        }
        let afterRefusal = try MacTweakJournal.decode(Data(contentsOf: fake.journalFile))
        precondition(afterRefusal.entries.isEmpty, "A refused write must not claim a journal entry")
        fake.state.withLock {
            $0.refuseWrites.removeAll()
            $0.values[statusBar] = .bool(true)
        }
        let undoRefused = try await restoreStore.undoEverything()
        precondition(undoRefused.isEmpty)
        precondition(fake.state.withLock { $0.values[statusBar] } == .bool(true))

        fake.state.withLock { $0.values[statusBar] = nil }
        let paired = MacTweak(id: "paired", group: .finder, changes: [
            .preference(pathBar, .bool(true)), .preference(statusBar, .bool(true)),
        ])
        let pairedStore = MacTweaksStore(catalogue: [paired], system: fake.make())
        let pairedOn = try await pairedStore.set("paired", on: true)
        precondition(pairedOn.isEmpty)
        let pairedOff = try await pairedStore.set("paired", on: false)
        precondition(pairedOff.isEmpty)
        let repeatedOff = try await pairedStore.set("paired", on: false)
        precondition(repeatedOff.isEmpty)
        fake.state.withLock {
            precondition($0.values[pathBar] == nil && $0.values[statusBar] == nil)
        }
        let undoRemoval = try await pairedStore.undoEverything()
        precondition(undoRemoval.isEmpty)
        fake.state.withLock {
            precondition($0.values[pathBar] == .integer(1) && $0.values[statusBar] == nil)
        }

        struct Tampered: Encodable { let entries: [MacTweakJournal.Entry] }
        let foreign = MacTweakTarget.preference(domain: "com.example.other", key: "Anything")
        let tampered = try JSONEncoder().encode(Tampered(entries: [
            .init(tweakID: "path", target: foreign, previous: .string("theirs"), written: .bool(true),
                  restarts: [.dock], date: Date(timeIntervalSince1970: 1)),
            .init(tweakID: "path", target: pathBar, previous: .string("theirs"), written: .string("not ours"),
                  restarts: [.dock], date: Date(timeIntervalSince1970: 1)),
        ]))
        try tampered.write(to: fake.journalFile)
        fake.state.withLock {
            $0.values[foreign] = .bool(true)
            $0.values[pathBar] = .string("not ours")
            $0.writes.removeAll()
            $0.restarts.removeAll()
        }
        let untrusted = try await restoreStore.undoEverything()
        precondition(untrusted.isEmpty)
        let untrustedSnapshot = try await restoreStore.snapshot()
        precondition(untrustedSnapshot.journaled.isEmpty)
        fake.state.withLock {
            precondition($0.writes.isEmpty && $0.restarts.isEmpty, "Untrusted entries must never be acted on")
            $0.values[foreign] = nil
            $0.values[pathBar] = .integer(1)
        }
        let afterTampering = try Data(contentsOf: fake.journalFile)
        precondition(afterTampering == tampered)
        try FileManager.default.removeItem(at: fake.journalFile)

        let heldOn = MacTweakTarget.preference(domain: "com.example.finder", key: "HeldOn")
        let fallbackOff = MacTweakTarget.preference(domain: "com.example.finder", key: "FallbackOff")
        fake.state.withLock { $0.fallback = [heldOn: .bool(true), fallbackOff: .bool(false)] }
        let fallbackStore = MacTweaksStore(catalogue: [
            MacTweak(id: "held-on", group: .finder, changes: [.preference(heldOn, .bool(true))]),
            MacTweak(id: "fallback-off", group: .finder, changes: [.preference(fallbackOff, .bool(true))]),
        ], system: fake.make())
        let fallbackStates = try await fallbackStore.snapshot().states
        precondition(fallbackStates["held-on"] == .heldElsewhere(.everyApp), "A fallback holding it on blocks")
        precondition(fallbackStates["fallback-off"] == .notApplied, "A fallback holding it off does not block")
        let heldOff = try await fallbackStore.set("held-on", on: false)
        guard case .blocked("held-on", .heldElsewhere(.everyApp))? = heldOff.first
        else { preconditionFailure("Turning off a fallback's value must report why") }
        let fallbackOn = try await fallbackStore.set("fallback-off", on: true)
        precondition(fallbackOn.isEmpty)
        precondition(fake.state.withLock { $0.values[fallbackOff] } == .bool(true))
        let overFallback = try await fallbackStore.snapshot()
        precondition(overFallback.states["fallback-off"] == .applied)
        let backToFallback = try await fallbackStore.set("fallback-off", on: false)
        precondition(backToFallback.isEmpty)
        fake.state.withLock {
            precondition($0.values[fallbackOff] == nil && $0.values[heldOn] == nil)
            $0.fallback = [:]
        }

        // Real child processes, never a system command: these check only the live interface's process rules.
        _ = try MacTweaksSystem.run("/bin/sh", ["-c", "exit 1"]).checked(accepting: MacTweaksSystem.killallDone)
        do {
            _ = try MacTweaksSystem.run("/bin/sh", ["-c", "exit 2"]).checked(accepting: MacTweaksSystem.killallDone)
            preconditionFailure("A restart that failed must still throw")
        } catch {}
        do {
            // An OS timer contract: the sleep's own 5 s caps the wait if the limit never fires.
            _ = try MacTweaksSystem.run("/bin/sleep", ["5"], timeout: 0.2)
            preconditionFailure("A hung child process must be stopped")
        } catch {}

        let corrupt = Data("keep these bytes".utf8)
        try corrupt.write(to: fake.journalFile)
        let writesBeforeCorruption = fake.state.withLock { $0.writes.count }
        do {
            _ = try await restoreStore.runPreset(.recommended)
            preconditionFailure("Corruption must block the batch")
        } catch MacTweaksStore.Failure.corruptJournal {}
        let afterCorruption = try Data(contentsOf: fake.journalFile)
        precondition(afterCorruption == corrupt)
        precondition(fake.state.withLock { $0.writes.count } == writesBeforeCorruption)
        print("Mac Tweaks store passed")
    }
}
