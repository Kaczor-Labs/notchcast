// Adapted from RemoveMacAI (omlahore, 12cef18, MIT) and Peel (Dragos Tugui, 2023079, GPL-3.0).
import Foundation

@MainActor
final class MacTweaksStore {
    enum Failure: Error, Equatable {
        case busy
        case unknownTweak
        case corruptJournal
        case unverifiedJournal
        case superseded
    }

    enum Issue: Sendable {
        case blocked(MacTweak.ID, MacTweakState)
        case change(MacTweak.ID, MacTweakTarget, any Error)
        case restart(MacTweakRestart, any Error)
        case skipped(MacTweak.ID, MacTweakTarget)
    }

    private enum Request: Sendable {
        case set(MacTweak.ID, Bool)
        case undoEverything
    }

    private enum WriteFailure: Error { case valueDidNotChange, valueChangedExternally, heldByEarlierEntry }

    private let system: MacTweaksSystem
    private let catalogue: [MacTweak]
    private(set) var isBusy = false
    private var revision = 0
    private var issued = 0
    private var issuedRevision: Int?

    init(catalogue: [MacTweak], system: MacTweaksSystem) {
        self.catalogue = catalogue
        self.system = system
    }

    // Reads without waiting for an operation, as Peel's refresh; the pane reads again after each one.
    func snapshot() async throws -> MacTweakSnapshot {
        issued += 1
        let sequence = issued
        issuedRevision = isBusy ? nil : revision
        var snapshot = try await Self.readSnapshot(catalogue: catalogue, system: system)
        snapshot.sequence = sequence
        return snapshot
    }

    // Current while no newer snapshot was asked for and no operation ran since this one began.
    func isCurrent(_ snapshot: MacTweakSnapshot) -> Bool {
        snapshot.sequence == issued && issuedRevision == revision
    }

    func set(_ id: MacTweak.ID, on: Bool) async throws -> [Issue] {
        try await perform(.set(id, on))
    }

    func undoEverything() async throws -> [Issue] {
        try await perform(.undoEverything)
    }

    private func perform(_ request: Request) async throws -> [Issue] {
        guard !isBusy else { throw Failure.busy }
        isBusy = true
        revision += 1
        defer {
            isBusy = false
            revision += 1
        }
        return try await Self.run(request, catalogue: catalogue, system: system)
    }

    @concurrent
    private static func readSnapshot(catalogue: [MacTweak], system: MacTweaksSystem) async throws -> MacTweakSnapshot {
        let url = file(in: system)
        var journal = try loadJournal(url)
        // A journal unchanged across the system read pairs each value with its undo data.
        for _ in 0..<3 {
            try Task.checkCancellation()
            let snapshot = snapshot(catalogue, journal: journal, system: system)
            let after = try loadJournal(url)
            if after == journal { return snapshot }
            journal = after
        }
        throw Failure.superseded
    }

    @concurrent
    private static func run(
        _ request: Request, catalogue: [MacTweak], system: MacTweaksSystem
    ) async throws -> [Issue] {
        try Task.checkCancellation()
        var batch = try Batch(system: system, catalogue: catalogue)
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
        let supported = catalogue.filter { $0.isSupported(on: system.version) }
        let readings = system.readAll(supported.flatMap { $0.changes.compactMap(\.localWrite?.target) })
        let states = catalogue.map { ($0.id, state(of: $0, version: system.version, readings: readings)) }
        return MacTweakSnapshot(
            states: Dictionary(uniqueKeysWithValues: states),
            journaled: Set(journal.restoreAll(known: catalogue).map(\.tweakID))
        )
    }

    private nonisolated static func state(
        of tweak: MacTweak,
        version: OperatingSystemVersion,
        readings: [MacTweakTarget: Result<MacTweaksSystem.Reading, any Error>]
    ) -> MacTweakState {
        guard tweak.isSupported(on: version), !tweak.changes.isEmpty else { return .unsupported }
        var applied = 0
        var blocked: MacTweakState?
        for change in tweak.changes {
            guard let (target, value) = change.localWrite else { return .unsupported }
            guard case .success(let reading)? = readings[target] else { return .unavailable }
            if reading.managed { return .managed }
            blocked = blocked ?? reading.block(wanting: value)
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
        let catalogue: [MacTweak]
        var journal: MacTweakJournal
        var restarts: Set<MacTweakRestart> = []
        var issues: [Issue] = []

        init(system: MacTweaksSystem, catalogue: [MacTweak]) throws {
            self.system = system
            self.catalogue = catalogue
            journal = try loadJournal(file(in: system))
        }

        mutating func run(_ request: Request, catalogue: [MacTweak]) throws {
            switch request {
            case .set(let id, let on):
                guard let tweak = catalogue.first(where: { $0.id == id }),
                      let state = snapshot([tweak], journal: journal, system: system).states[id]
                else { throw Failure.unknownTweak }
                guard state.canChange else {
                    issues.append(.blocked(id, state))
                    return
                }
                if on, state != .applied {
                    for change in tweak.changes {
                        if let (target, value) = change.localWrite {
                            try apply(tweak, target: target, value: value)
                        }
                    }
                } else if !on {
                    try setOff(tweak, state: state)
                }
            case .undoEverything:
                for entry in journal.entries.reversed() where !entry.isKnown(by: catalogue) {
                    issues.append(.skipped(entry.tweakID, entry.target))
                }
                for entry in journal.restoreAll(known: catalogue) { try restore(entry) }
            }
        }

        mutating func setOff(_ tweak: MacTweak, state: MacTweakState) throws {
            let recorded = journal.restoreAll(known: catalogue).filter { $0.tweakID == tweak.id }
            for entry in recorded where entry.target != .libraryHidden || entry.written != .bool(true) {
                try restore(entry, includingRemovals: false)
            }
            guard state == .applied || state == .partial else { return }
            for change in tweak.changes {
                guard let (target, value) = change.localWrite else { continue }
                let offValue: MacTweakValue?
                switch target {
                case .preference: offValue = nil
                case .libraryHidden: offValue = .bool(true)
                case .service: continue
                }
                try Task.checkCancellation()
                guard !isHeldByEarlierEntry(target, tweakID: tweak.id),
                      let reading = writableReading(target, tweakID: tweak.id),
                      value.matches(reading.stored),
                      !journal.entries.contains(where: { $0.target == target.canonical && $0.owns(reading.stored) })
                else { continue }
                try recordAndWrite(tweak, target: target, value: offValue, previous: reading.stored)
            }
        }

        mutating func apply(_ tweak: MacTweak, target: MacTweakTarget, value: MacTweakValue) throws {
            try Task.checkCancellation()
            guard let reading = writableReading(target, tweakID: tweak.id),
                  !value.matches(reading.effective),
                  !isHeldByEarlierEntry(target, tweakID: tweak.id) else { return }
            if let entry = journal.entries.first(where: { $0.target == target.canonical && $0.tweakID == tweak.id }),
               entry.owns(reading.stored), value.matches(entry.previous) {
                try restore(entry)
            } else {
                try recordAndWrite(tweak, target: target, value: value, previous: reading.stored)
            }
        }

        mutating func recordAndWrite(
            _ tweak: MacTweak, target: MacTweakTarget, value: MacTweakValue?, previous: MacTweakValue?
        ) throws {
            guard let next = journal.apply(tweak, target: target, value: value, current: previous, now: system.now())
            else { return }
            let before = journal
            try save(next)
            guard stillWritable(target, replacing: previous, tweakID: tweak.id) else {
                try save(before)
                return
            }
            guard write(target, value: value, tweakID: tweak.id) else {
                if let actual = readOrReport(target, tweakID: tweak.id), actual.block == nil, actual.stored != value {
                    try save(before)
                }
                return
            }
            restarts.formUnion(tweak.restarts)
            if next.entries.last?.hasSupersededWrite == true {
                var completed = next
                completed.finishWrite(target)
                try save(completed)
            }
        }

        mutating func restore(_ entry: MacTweakJournal.Entry, includingRemovals: Bool = true) throws {
            try Task.checkCancellation()
            guard let reading = writableReading(entry.target, tweakID: entry.tweakID) else { return }
            if case .write(let previous) = journal.restore(entry, current: reading.stored) {
                guard includingRemovals || entry.written != nil else { return }
                guard stillWritable(entry.target, replacing: reading.stored, tweakID: entry.tweakID),
                      write(entry.target, value: previous, tweakID: entry.tweakID)
                else { return }
                restarts.formUnion(entry.restarts)
            }
            var next = journal
            next.forget(entry.target)
            try save(next)
        }

        // An entry only a retired or unknown tweak explains waits for Undo Everything; writing would bury it.
        mutating func isHeldByEarlierEntry(_ target: MacTweakTarget, tweakID: MacTweak.ID) -> Bool {
            guard let entry = journal.entries.first(where: { $0.target == target.canonical }),
                  !entry.isKnown(by: catalogue.filter { !$0.isRetired }) else { return false }
            issues.append(.change(tweakID, target, WriteFailure.heldByEarlierEntry))
            return true
        }

        mutating func writableReading(_ target: MacTweakTarget, tweakID: MacTweak.ID) -> MacTweaksSystem.Reading? {
            guard let reading = readOrReport(target, tweakID: tweakID) else { return nil }
            if let block = reading.block {
                issues.append(.blocked(tweakID, block))
                return nil
            }
            return reading
        }

        mutating func readOrReport(_ target: MacTweakTarget, tweakID: MacTweak.ID) -> MacTweaksSystem.Reading? {
            do {
                return try system.read(target)
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
