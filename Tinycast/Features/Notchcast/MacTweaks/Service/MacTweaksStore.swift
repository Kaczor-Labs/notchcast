// Adapted from RemoveMacAI (omlahore, 12cef18, MIT) and Peel (Dragos Tugui, 2023079, GPL-3.0).
import Foundation

@MainActor
final class MacTweaksStore {
    enum Failure: Error, Equatable {
        case busy
        case unknownTweak
        case corruptJournal
        case unverifiedJournal
    }

    enum Issue: Sendable {
        case blocked(MacTweak.ID, MacTweakState)
        case change(MacTweak.ID, MacTweakTarget, any Error)
        case restart(MacTweakRestart, any Error)
    }

    private enum Request: Sendable {
        case set(MacTweak.ID, Bool)
        case preset(MacTweakPreset)
        case undoEverything
    }

    private enum WriteFailure: Error { case valueDidNotChange, valueChangedExternally }

    private let system: MacTweaksSystem
    private let catalogue: [MacTweak]
    private(set) var isBusy = false

    init(catalogue: [MacTweak], system: MacTweaksSystem) {
        self.catalogue = catalogue
        self.system = system
    }

    func snapshot() async throws -> MacTweakSnapshot {
        guard !isBusy else { throw Failure.busy }
        isBusy = true
        defer { isBusy = false }
        return try await Self.readSnapshot(catalogue: catalogue, system: system)
    }

    func set(_ id: MacTweak.ID, on: Bool) async throws -> [Issue] {
        try await perform(.set(id, on))
    }

    func runPreset(_ preset: MacTweakPreset) async throws -> [Issue] {
        try await perform(.preset(preset))
    }

    func undoEverything() async throws -> [Issue] {
        try await perform(.undoEverything)
    }

    private func perform(_ request: Request) async throws -> [Issue] {
        guard !isBusy else { throw Failure.busy }
        isBusy = true
        defer { isBusy = false }
        return try await Self.run(request, catalogue: catalogue, system: system)
    }

    @concurrent
    private static func readSnapshot(catalogue: [MacTweak], system: MacTweaksSystem) async throws -> MacTweakSnapshot {
        try Task.checkCancellation()
        return snapshot(catalogue, journal: try loadJournal(file(in: system)), system: system)
    }

    @concurrent
    private static func run(
        _ request: Request, catalogue: [MacTweak], system: MacTweaksSystem
    ) async throws -> [Issue] {
        try Task.checkCancellation()
        var batch = try Batch(system: system)
        do {
            try batch.run(request, catalogue: catalogue)
        } catch {
            batch.restartProcesses()
            throw error
        }
        batch.restartProcesses()
        return batch.issues
    }

    private nonisolated static func snapshot(
        _ catalogue: [MacTweak], journal: MacTweakJournal, system: MacTweaksSystem
    ) -> MacTweakSnapshot {
        let states = catalogue.map { ($0.id, state(of: $0, system: system)) }
        return MacTweakSnapshot(
            states: Dictionary(uniqueKeysWithValues: states),
            journaled: Set(journal.entries.map(\.tweakID))
        )
    }

    private nonisolated static func state(of tweak: MacTweak, system: MacTweaksSystem) -> MacTweakState {
        guard tweak.isSupported(on: system.version), !tweak.changes.isEmpty else { return .unsupported }
        var applied = 0
        var blocked: MacTweakState?
        for change in tweak.changes {
            guard let (target, value) = change.localWrite else { return .unsupported }
            guard let reading = try? system.read(target) else { return .unavailable }
            if reading.managed { return .managed }
            blocked = blocked ?? reading.block
            if value.matches(reading.effective) { applied += 1 }
        }
        if let blocked { return blocked }
        if applied == tweak.changes.count { return .applied }
        return applied == 0 ? .notApplied : .partial
    }

    private nonisolated static func file(in system: MacTweaksSystem) -> URL {
        system.journalFolder.appending(path: "journal.json")
    }

    private nonisolated static func loadJournal(_ url: URL) throws -> MacTweakJournal {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return MacTweakJournal()
        }
        do {
            return try MacTweakJournal.decode(data)
        } catch {
            throw Failure.corruptJournal
        }
    }

    private nonisolated struct Batch {
        let system: MacTweaksSystem
        var journal: MacTweakJournal
        var restarts: Set<MacTweakRestart> = []
        var issues: [Issue] = []

        init(system: MacTweaksSystem) throws {
            self.system = system
            journal = try loadJournal(file(in: system))
        }

        mutating func run(_ request: Request, catalogue: [MacTweak]) throws {
            switch request {
            case .set(let id, let on):
                guard let tweak = catalogue.first(where: { $0.id == id }) else { throw Failure.unknownTweak }
                let snapshot = snapshot([tweak], journal: journal, system: system)
                if let block = snapshot.states[id], !block.canChange {
                    issues.append(.blocked(id, block))
                    return
                }
                try execute(MacTweakPlan.make(
                    wanted: on ? [id] : [], catalogue: [tweak], snapshot: snapshot, undo: on ? [] : [id]
                ))
            case .preset(let preset):
                let snapshot = snapshot(catalogue, journal: journal, system: system)
                let wanted = preset.wanted(in: catalogue)
                for id in wanted.sorted() {
                    if let state = snapshot.states[id], !state.canChange {
                        issues.append(.blocked(id, state))
                    }
                }
                let selected = catalogue.filter { wanted.contains($0.id) }
                try execute(MacTweakPlan.make(wanted: wanted, catalogue: selected, snapshot: snapshot))
            case .undoEverything:
                for entry in journal.restoreAll() { try restore(entry) }
            }
        }

        mutating func execute(_ plan: MacTweakPlan) throws {
            for entry in journal.restoreAll() where plan.restore.contains(entry.tweakID) {
                try restore(entry)
            }
            for tweak in plan.apply {
                for change in tweak.changes {
                    if let (target, value) = change.localWrite {
                        try apply(tweak, target: target, value: value)
                    }
                }
            }
        }

        mutating func apply(_ tweak: MacTweak, target: MacTweakTarget, value: MacTweakValue) throws {
            try Task.checkCancellation()
            guard let reading = writableReading(target, tweakID: tweak.id),
                  !value.matches(reading.effective),
                  let next = journal.apply(tweak, target: target, value: value, current: reading.stored, now: system.now())
            else { return }
            let before = journal
            try save(next)
            guard stillWritable(target, replacing: reading.stored, tweakID: tweak.id) else {
                try save(before)
                return
            }
            guard write(target, value: value, tweakID: tweak.id) else { return }
            restarts.formUnion(tweak.restarts)
            if next.entries.last?.supersededWrite != nil {
                var completed = next
                completed.finishWrite(target)
                try save(completed)
            }
        }

        mutating func restore(_ entry: MacTweakJournal.Entry) throws {
            try Task.checkCancellation()
            guard let reading = writableReading(entry.target, tweakID: entry.tweakID) else { return }
            if case .write(let previous) = journal.restore(entry, current: reading.stored) {
                guard stillWritable(entry.target, replacing: reading.stored, tweakID: entry.tweakID),
                      write(entry.target, value: previous, tweakID: entry.tweakID)
                else { return }
                restarts.formUnion(entry.restarts)
            }
            var next = journal
            next.forget(entry.target)
            try save(next)
        }

        mutating func writableReading(_ target: MacTweakTarget, tweakID: MacTweak.ID) -> MacTweaksSystem.Reading? {
            do {
                let reading = try system.read(target)
                if let block = reading.block {
                    issues.append(.blocked(tweakID, block))
                    return nil
                }
                return reading
            } catch {
                issues.append(.change(tweakID, target, error))
                return nil
            }
        }

        mutating func stillWritable(
            _ target: MacTweakTarget, replacing previous: MacTweakValue?, tweakID: MacTweak.ID
        ) -> Bool {
            guard let reading = writableReading(target, tweakID: tweakID) else { return false }
            guard reading.stored == previous else {
                issues.append(.change(tweakID, target, WriteFailure.valueChangedExternally))
                return false
            }
            return true
        }

        mutating func write(_ target: MacTweakTarget, value: MacTweakValue?, tweakID: MacTweak.ID) -> Bool {
            do {
                try system.write(target, value)
                guard try system.read(target).stored == value else { throw WriteFailure.valueDidNotChange }
                return true
            } catch {
                issues.append(.change(tweakID, target, error))
                return false
            }
        }

        mutating func save(_ next: MacTweakJournal) throws {
            try FileManager.default.createDirectory(at: system.journalFolder, withIntermediateDirectories: true)
            let url = file(in: system)
            try JSONEncoder().encode(next).write(to: url, options: .atomic)
            guard try loadJournal(url) == next else { throw Failure.unverifiedJournal }
            journal = next
        }

        mutating func restartProcesses() {
            for process in MacTweakRestart.allCases where restarts.contains(process) {
                do {
                    try system.restart(process)
                } catch {
                    issues.append(.restart(process, error))
                }
            }
        }
    }
}
