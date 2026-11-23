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

        func make(beforeRestart: @escaping @Sendable () -> Void = {}) -> MacTweaksSystem {
            MacTweaksSystem(
                version: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0),
                journalFolder: folder,
                read: { target in
                    self.state.withLock { state in
                        MacTweaksSystem.Reading(
                            stored: state.values[target],
                            effective: state.values[target],
                            managed: state.managed.contains(target),
                            heldElsewhere: state.elsewhere[target]
                        )
                    }
                },
                write: { target, value in
                    let journal = try MacTweakJournal.decode(Data(contentsOf: self.journalFile))
                    self.state.withLock { state in
                        let entry = journal.entries.first { $0.target == target }
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
        do {
            _ = try await store.snapshot()
            preconditionFailure("A snapshot must not interrupt a running batch")
        } catch MacTweaksStore.Failure.busy {}
        release.signal()
        let applied = try await running.value
        precondition(applied.isEmpty)
        precondition(!store.isBusy)
        let after = try await store.snapshot()
        precondition(after.applied == ["path", "status", "media-keys"])
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
            precondition($0.values == start, "Undo must include entries missing from the current catalogue")
            precondition($0.restarts == [.finder])
            precondition(!$0.writes.contains(locked) && !$0.writes.contains(inherited))
        }

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
