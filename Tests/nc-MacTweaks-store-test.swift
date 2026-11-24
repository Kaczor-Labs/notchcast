// notchcast-sources: Tinycast/Features/Notchcast/MacTweaks/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/MacTweaks/Service/*.swift
// notchcast-sources: Tinycast/Platform/AppPaths.swift
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

        func make(duringReadAll: @escaping @Sendable () -> Void = {}) -> MacTweaksSystem {
            MacTweaksSystem(
                version: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0),
                journalFolder: folder,
                read: { target in
                    self.state.withLock { $0.reads += 1 }
                    return self.reading(target)
                },
                readAll: { targets in
                    self.state.withLock { $0.readAlls += 1 }
                    duringReadAll()
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
        let applied = try await running.value
        precondition(applied.isEmpty)
        precondition(!store.isBusy)
        let statusApplied = try await store.set("status", on: true)
        let serviceApplied = try await store.set("media-keys", on: true)
        precondition(statusApplied.isEmpty && serviceApplied.isEmpty)
        let readsBefore = fake.state.withLock { ($0.reads, $0.readAlls) }
        let after = try await store.snapshot()
        precondition(fake.state.withLock { ($0.reads, $0.readAlls) } == (readsBefore.0, readsBefore.1 + 1),
                     "A snapshot reads every target in one pass")
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
            precondition($0.restarts == [.finder, .finder, .finder])
            $0.restarts.removeAll()
        }
        let reapplied = try await restoreStore.set("path", on: true)
        precondition(reapplied.isEmpty)
        fake.state.withLock { $0.restarts.removeAll() }

        let undone = try await restoreStore.undoEverything()
        guard undone.count == 1, case .skipped("media-keys", service)? = undone.first
        else { preconditionFailure("Undo must report an entry it left in place") }
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
        var retired = catalogue
        retired[4].isRetired = true
        let retiredStore = MacTweaksStore(catalogue: retired, system: fake.make())
        let retiredStates = try await retiredStore.snapshot()
        precondition(retiredStates.states["media-keys"] == .unsupported && retiredStates.journaled == ["media-keys"])
        let fullUndo = try await retiredStore.undoEverything()
        precondition(fullUndo.isEmpty, "A retired tweak's entry is restored")
        precondition(fake.state.withLock { $0.values } == start)

        let oldID = MacTweak(id: "old-path", group: .finder, changes: [.preference(pathBar, .bool(true))])
        let replacement = MacTweak(id: "new-path", group: .finder, changes: [.preference(pathBar, .bool(true))])
        let otherValue = MacTweak(id: "new-path", group: .finder, changes: [.preference(pathBar, .integer(2))])
        let oldOn = try await MacTweaksStore(catalogue: [oldID], system: fake.make()).set("old-path", on: true)
        precondition(oldOn.isEmpty)
        let oldJournal = try Data(contentsOf: fake.journalFile)
        for (tweak, on) in [(replacement, false), (otherValue, true)] {
            let result = try await MacTweaksStore(catalogue: [tweak], system: fake.make()).set("new-path", on: on)
            guard result.count == 1, case .change("new-path", pathBar, _)? = result.first
            else { preconditionFailure("A write over an entry no active tweak explains must report it") }
            let journalNow = try Data(contentsOf: fake.journalFile)
            precondition(journalNow == oldJournal, "The earlier entry must stay")
            precondition(fake.state.withLock { $0.values[pathBar] } == .bool(true))
        }
        var oldRetired = oldID
        oldRetired.isRetired = true
        let oldUndo = try await MacTweaksStore(catalogue: [oldRetired, replacement], system: fake.make()).undoEverything()
        precondition(oldUndo.isEmpty)
        precondition(fake.state.withLock { $0.values } == start)

        let racing = Mutex(true)
        let windowStore = MacTweaksStore(catalogue: catalogue, system: fake.make(duringReadAll: {
            guard racing.withLock({ first in defer { first = false }; return first }) else { return }
            let entry = MacTweakJournal().apply(
                catalogue[1], target: statusBar, value: .bool(true), current: nil, now: Date(timeIntervalSince1970: 100)
            )!
            do {
                try JSONEncoder().encode(entry).write(to: fake.journalFile, options: .atomic)
            } catch {
                preconditionFailure("The racing journal write failed: \(error)")
            }
            fake.state.withLock { $0.values[statusBar] = .bool(true) }
        }))
        let window = try await windowStore.snapshot()
        precondition(window.states["status"] == .applied && window.journaled.contains("status"),
                     "A write during the read must come with its undo entry")
        precondition(windowStore.isCurrent(window))
        let newer = try await windowStore.snapshot()
        precondition(!windowStore.isCurrent(window) && windowStore.isCurrent(newer), "An older snapshot is superseded")
        let windowUndo = try await windowStore.undoEverything()
        precondition(windowUndo.isEmpty && !windowStore.isCurrent(newer), "An operation supersedes a snapshot")
        precondition(fake.state.withLock { $0.values } == start)

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
        let blind = Mutex(false)
        let seeing = fake.make()
        let blindAfterWrite = MacTweaksSystem(
            version: seeing.version, journalFolder: seeing.journalFolder,
            read: { target in
                guard !blind.withLock({ $0 }) else { throw FakeFailure.write }
                return try seeing.read(target)
            },
            readAll: seeing.readAll,
            write: { target, value in
                blind.withLock { $0 = true }
                try seeing.write(target, value)
            },
            restart: seeing.restart, now: seeing.now)
        let unread = try await MacTweaksStore(catalogue: catalogue, system: blindAfterWrite).set("status", on: true)
        precondition(unread.count == 2, "A refused write and the failed read after it must both be reported")
        let unconfirmed = try MacTweakJournal.decode(Data(contentsOf: fake.journalFile))
        precondition(unconfirmed.entries.map(\.target) == [statusBar], "An unconfirmed write keeps its entry")
        let forgotten = try await restoreStore.undoEverything()
        precondition(forgotten.isEmpty && fake.state.withLock { $0.values[statusBar] } == nil)
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
        guard untrusted.count == 2, case .skipped("path", pathBar)? = untrusted.first,
              case .skipped("path", foreign)? = untrusted.last
        else { preconditionFailure("Undo must report each untrusted entry it skipped") }
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
        let fallbackUndo = try await fallbackStore.undoEverything()
        let fallbackJournal = try MacTweakJournal.decode(Data(contentsOf: fake.journalFile))
        precondition(fallbackUndo.isEmpty && fallbackJournal.entries.isEmpty, "Undo Everything forgets a settled entry")

        let beforeRewrite = try await restoreStore.set("status", on: true)
        fake.state.withLock { $0.values[statusBar] = .string("YES") }
        let rewrittenOff = try await restoreStore.set("status", on: false)
        precondition(beforeRewrite.isEmpty && rewrittenOff.isEmpty)
        precondition(fake.state.withLock { $0.values[statusBar] } == nil, "A value rewritten elsewhere must still turn off")
        let rewrittenUndo = try await restoreStore.undoEverything()
        precondition(rewrittenUndo.isEmpty && fake.state.withLock { $0.values[statusBar] } == nil,
                     "Undo Everything must not bring back a value set elsewhere between two changes")

        try processRules()
        try domainSyncRules()
        try await refusedSaveRules(in: folder.appending(path: "refused"))
        try await firstValueRules(in: folder.appending(path: "first"))

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
        let hidden = try await reopened.store.set("show-library", on: false)
        fake.state.withLock { $0.values[.libraryHidden] = .bool(false) }
        let hiddenAgain = try await reopened.store.set("show-library", on: false)
        precondition(hidden.isEmpty && hiddenAgain.isEmpty)
        precondition(fake.state.withLock { $0.values[.libraryHidden] } == .bool(true),
                     "Library shown again from Finder must still hide")
    }

    // The live interface on a preference domain named by a path in the temporary folder, never a system one.
    @MainActor
    static func refusedSaveRules(in folder: URL) async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let domain = folder.appending(path: "refused").path
        let file = domain + ".plist"
        try PropertyListSerialization.data(fromPropertyList: ["Other": 0], format: .binary, options: 0)
            .write(to: URL(filePath: file))
        let target = MacTweakTarget.preference(domain: domain, key: "Tweak")
        let live = MacTweaksSystem.live()
        let system = MacTweaksSystem(
            version: live.version, journalFolder: folder, read: live.read, readAll: live.readAll, write: live.write,
            restart: { _ in preconditionFailure("This tweak restarts nothing") }, now: live.now)
        let store = MacTweaksStore(catalogue: [
            MacTweak(id: "tweak", group: .finder, changes: [.preference(target, .bool(true))]),
        ], system: system)

        precondition(chflags(file, UInt32(UF_IMMUTABLE)) == 0)
        let refused = try await store.set("tweak", on: true)
        precondition(chflags(file, 0) == 0)
        guard refused.count == 1, case .change("tweak", target, _)? = refused.first
        else { preconditionFailure("A save the system refused must be reported") }
        let off = try await store.snapshot()
        precondition(off.states["tweak"] == .notApplied && off.journaled.isEmpty,
                     "A refused save must read as off with nothing to undo")
        let journal = try MacTweakJournal.decode(Data(contentsOf: folder.appending(path: "journal.json")))
        precondition(journal.entries.isEmpty, "A refused save must not keep its journal entry")

        let saved = try await store.set("tweak", on: true)
        let on = try await store.snapshot()
        precondition(saved.isEmpty && on.states["tweak"] == .applied && on.journaled == ["tweak"])
        let undone = try await store.undoEverything()
        let restored = try await store.snapshot()
        precondition(undone.isEmpty && restored.states["tweak"] == .notApplied && restored.journaled.isEmpty)
    }

    // Undo Everything returns each target to its value before the first change, whatever happened between.
    @MainActor
    static func firstValueRules(in folder: URL) async throws {
        let title = MacTweakTarget.preference(domain: "com.apple.finder", key: "_FXShowPosixPathInTitle")
        let status = MacTweakTarget.preference(domain: "com.apple.finder", key: "ShowStatusBar")
        let initial: [MacTweakTarget: MacTweakValue] = [status: .integer(0), .libraryHidden: .bool(true)]
        let fake = FakeSystem(folder: folder)
        fake.state.withLock { $0.values = initial }
        let store = MacTweaksStore(catalogue: MacTweakCatalog.finder, system: fake.make())
        func set(_ id: MacTweak.ID, _ on: Bool) async throws {
            let issues = try await store.set(id, on: on)
            precondition(issues.isEmpty)
        }

        try await set("path-in-title", true)
        fake.state.withLock { $0.values[title] = .string("YES") }
        try await set("path-in-title", false)
        precondition(fake.state.withLock { $0.values[title] } == nil)

        try await set("show-library", true)
        try await set("show-library", false)
        fake.state.withLock { $0.values[.libraryHidden] = .bool(false) }
        try await set("show-library", false)
        precondition(fake.state.withLock { $0.values[.libraryHidden] } == .bool(true))

        try await set("status-bar", true)
        try await set("status-bar", false)
        fake.state.withLock { $0.values[status] = .bool(true) }
        try await set("status-bar", false)

        let issues = try await store.undoEverything()
        precondition(issues.isEmpty)
        precondition(fake.state.withLock { $0.values } == initial,
                     "Undo Everything must return every target to its value before the first change")
        let journal = try MacTweakJournal.decode(Data(contentsOf: fake.journalFile))
        precondition(journal.entries.isEmpty)

        try await set("status-bar", true)
        try await set("status-bar", false)
        let idle = try await store.snapshot()
        precondition(idle.journaled.isEmpty, "Nothing is left to undo once every target holds its first value")
    }

    // Real child processes, never a system command: these check only the live interface's process rules.
    static func processRules() throws {
        typealias Live = MacTweaksSystem
        let noMatch = Live.CommandResult(name: "killall", status: 1, output: "No matching processes were found\n")
        try Live.checkedRestart(noMatch)
        let refused = Live.CommandResult(name: "killall", status: 1, output: "kill: Operation not permitted\n")
        do {
            try Live.checkedRestart(refused)
            preconditionFailure("A refused restart must throw")
        } catch Live.LiveFailure.processFailed("killall", 1) {}

        let plain = try Live.run("/bin/sh", ["-c", "echo out; echo err >&2; exit 3"])
        precondition(plain.status == 3 && plain.output == "out\nerr\n")

        func expectStopped(_ script: String, within limit: Duration, _ message: String) throws {
            let clock = ContinuousClock()
            let began = clock.now
            do {
                _ = try Live.run("/bin/sh", ["-c", script], timeout: 0.2, grace: 0.3)
                preconditionFailure(message)
            } catch Live.LiveFailure.stopped("/bin/sh") {}
            precondition(clock.now - began < limit, message)
        }
        // A shell runs a trap only between commands, so each loop step is a short sleep.
        try expectStopped("trap 'exit 0' TERM; while :; do sleep 0.05; done", within: .seconds(3),
                          "A child that exits zero after TERM still timed out")
        try expectStopped("trap '' TERM; while :; do sleep 0.05; done", within: .seconds(3),
                          "A child that ignores TERM must be killed")

        let clock = ContinuousClock()
        let began = clock.now
        let held = try Live.run("/bin/sh", ["-c", "sleep 5 & echo done"], drain: 0.2)
        precondition(held.status == 0 && held.output == "done\n")
        precondition(clock.now - began < .seconds(3), "A descendant holding the pipe must not hold the result")
    }

    static func domainSyncRules() throws {
        let calls = Mutex(0)
        let sync = MacTweaksSystem.DomainSync { _ in
            calls.withLock { $0 += 1 }
            throw FakeFailure.write
        }
        for _ in 0..<2 {
            do {
                try sync("com.example.finder")
                preconditionFailure("A failed sync must fail every key of its domain")
            } catch FakeFailure.write {}
        }
        try? sync(".GlobalPreferences")
        try? sync("NSGlobalDomain")
        precondition(calls.withLock { $0 } == 2, "Each domain synchronizes once per pass")
    }
}
