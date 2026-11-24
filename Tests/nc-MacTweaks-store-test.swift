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

        func make() -> MacTweaksSystem {
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
                     restarts: [.finder]),
            MacTweak(id: "status", group: .finder, changes: [.preference(statusBar, .bool(true))],
                     restarts: [.finder]),
            MacTweak(id: "locked", group: .finder, changes: [.preference(locked, .bool(true))]),
            MacTweak(id: "inherited", group: .finder, changes: [.preference(inherited, .bool(true))]),
            MacTweak(id: "media-keys", group: .annoyances, changes: [.service("com.example.media-keys")]),
        ]

        let module = MacTweaksModule(catalogue: catalogue, system: fake.make())
        module.start()
        let store = module.store
        let running = Task.immediate { try await store.set("path", on: true) }
        precondition(store.isBusy)
        do {
            _ = try await store.undoEverything()
            preconditionFailure("Concurrent mutations must be refused")
        } catch MacTweaksStore.Failure.busy {}
        do {
            _ = try await store.snapshot()
            preconditionFailure("A snapshot must not interrupt a running batch")
        } catch MacTweaksStore.Failure.busy {}
        do {
            _ = try await MacTweaksModule(catalogue: catalogue, system: fake.make()).store.set("status", on: true)
            preconditionFailure("A module rebuilt mid-batch must not write the journal at once")
        } catch MacTweaksStore.Failure.busy {}
        let applied = try await running.value
        precondition(applied.isEmpty)
        precondition(!store.isBusy)
        let statusApplied = try await store.set("status", on: true)
        let serviceApplied = try await store.set("media-keys", on: true)
        precondition(statusApplied.isEmpty && serviceApplied.isEmpty)
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
            precondition($0.restarts == [.finder, .finder, .finder])
            $0.restarts.removeAll()
        }
        let reapplied = try await restoreStore.set("path", on: true)
        precondition(reapplied.isEmpty)
        fake.state.withLock { $0.restarts.removeAll() }

        let undone = try await restoreStore.undoEverything()
        precondition(undone.isEmpty)
        fake.state.withLock {
            precondition($0.values == start, "Undo must include entries missing from the current catalogue")
            precondition($0.restarts == [.finder])
            precondition(!$0.writes.contains(locked) && !$0.writes.contains(inherited))
        }

        let beforeFailure = try await restoreStore.set("path", on: true)
        let secondChange = try await restoreStore.set("status", on: true)
        precondition(beforeFailure.isEmpty && secondChange.isEmpty)
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
            _ = try await restoreStore.set("path", on: true)
            preconditionFailure("Corruption must block the batch")
        } catch MacTweaksStore.Failure.corruptJournal {}
        let afterCorruption = try Data(contentsOf: fake.journalFile)
        precondition(afterCorruption == corrupt)
        precondition(fake.state.withLock { $0.writes.count } == writesBeforeCorruption)
        let finderFolder = folder.appending(path: "finder")
        try await checkFinderCatalogue(in: finderFolder)
        print("Mac Tweaks store and Finder catalogue passed")
    }
    @MainActor
    private static func checkFinderCatalogue(in folder: URL) async throws {
        let finder = MacTweakCatalog.finder
        let ids = finder.map(\.id)
        precondition(ids == [
            "file-extensions", "hidden-files", "path-bar", "status-bar", "folders-first",
            "search-this-folder", "extension-warning", "path-in-title", "network-ds-store",
            "trash-30-days", "save-locally", "expanded-save", "show-library",
        ])
        precondition(finder.allSatisfy { $0.group == .finder && $0.changes.count == 1 })
        let targets = finder.flatMap(\.changes).compactMap { $0.localWrite?.target }
        precondition(Set(targets).count == finder.count)

        let fake = FakeSystem(folder: folder)
        let initial: [MacTweakTarget: MacTweakValue] = [
            .preference(domain: "com.apple.finder", key: "ShowPathbar"): .integer(0),
            .preference(domain: "com.apple.finder", key: "FXDefaultSearchScope"): .string("SCev"),
            .libraryHidden: .bool(true),
        ]
        fake.state.withLock { $0.values = initial }
        let module = MacTweaksModule(catalogue: finder, system: fake.make())
        module.start()
        let initialSnapshot = try await module.store.snapshot()
        precondition(initialSnapshot.applied.isEmpty)
        for tweak in finder {
            let issues = try await module.store.set(tweak.id, on: true)
            let snapshot = try await module.store.snapshot()
            precondition(issues.isEmpty)
            precondition(snapshot.states[tweak.id] == .applied && snapshot.journaled.contains(tweak.id))
        }
        let enabled = try await module.store.snapshot()
        precondition(enabled.applied == Set(ids))
        precondition(fake.state.withLock { $0.writes } == targets)

        for tweak in finder {
            let issues = try await module.store.set(tweak.id, on: false)
            let snapshot = try await module.store.snapshot()
            precondition(issues.isEmpty && snapshot.states[tweak.id] == .notApplied)
        }
        precondition(fake.state.withLock { $0.values } == initial)

        for tweak in finder {
            let issues = try await module.store.set(tweak.id, on: true)
            precondition(issues.isEmpty)
        }
        module.stop()
        fake.state.withLock { $0.restarts.removeAll() }
        let reopened = MacTweaksModule(catalogue: finder, system: fake.make())
        reopened.start()
        let undoIssues = try await reopened.store.undoEverything()
        let restored = try await reopened.store.snapshot()
        precondition(undoIssues.isEmpty && restored.applied.isEmpty && restored.journaled.isEmpty)
        fake.state.withLock {
            precondition($0.values == initial)
            precondition($0.restarts == [.finder])
            $0.values[.libraryHidden] = .bool(false)
        }
        for _ in 0..<2 {
            let issues = try await reopened.store.set("show-library", on: false)
            precondition(issues.isEmpty)
            precondition(fake.state.withLock { $0.values[.libraryHidden] } == .bool(true))
        }
        let showAgain = try await reopened.store.set("show-library", on: true)
        let shown = try await reopened.store.snapshot()
        precondition(showAgain.isEmpty && shown.states["show-library"] == .applied && shown.journaled.isEmpty)
        let hideAgain = try await reopened.store.set("show-library", on: false)
        precondition(hideAgain.isEmpty)
        let undoHide = try await reopened.store.undoEverything()
        precondition(undoHide.isEmpty)
        precondition(fake.state.withLock { $0.values[.libraryHidden] } == .bool(false))
    }
}
