// Adapted from RemoveMacAI (omlahore, 12cef18, MIT) and Peel (Dragos Tugui, 2023079, GPL-3.0).
import Foundation

struct MacTweakJournal: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        let tweakID: MacTweak.ID
        let target: MacTweakTarget
        let previous: MacTweakValue?
        let written: MacTweakValue?
        let restarts: Set<MacTweakRestart>
        let date: Date
        var supersededWrite: MacTweakValue?
        var supersededRemoval: Bool?

        var hasSupersededWrite: Bool { supersededWrite != nil || supersededRemoval == true }

        func owns(_ current: MacTweakValue?) -> Bool {
            current == written || (hasSupersededWrite && current == supersededWrite)
        }
    }

    enum Restore: Equatable {
        case forget
        case write(MacTweakValue?)
    }

    enum InvalidJournal: Error {
        case invalidEntries
    }

    private(set) var entries: [Entry] = []

    func apply(
        _ tweak: MacTweak,
        target: MacTweakTarget,
        value: MacTweakValue?,
        current: MacTweakValue?,
        now: Date
    ) -> Self? {
        guard !(value?.matches(current) ?? (current == nil)) else { return nil }
        let owned = entries.first { $0.target == target && $0.owns(current) }
        var next = self
        next.forget(target)
        next.entries.append(Entry(
            tweakID: tweak.id,
            target: target,
            previous: owned == nil ? current : owned?.previous,
            written: value,
            restarts: tweak.restarts.union(owned?.restarts ?? []),
            date: owned?.date ?? now,
            supersededWrite: owned == nil ? nil : current,
            supersededRemoval: owned != nil && current == nil ? true : nil
        ))
        return next
    }

    func restore(_ entry: Entry, current: MacTweakValue?) -> Restore {
        entry.owns(current) && current != entry.previous ? .write(entry.previous) : .forget
    }

    func restoreAll() -> [Entry] {
        Array(entries.reversed())
    }

    mutating func forget(_ target: MacTweakTarget) {
        entries.removeAll { $0.target == target }
    }

    mutating func finishWrite(_ target: MacTweakTarget) {
        if let index = entries.firstIndex(where: { $0.target == target }) {
            entries[index].supersededWrite = nil
            entries[index].supersededRemoval = nil
        }
    }

    static func decode(_ data: Data) throws -> Self {
        let journal = try JSONDecoder().decode(Self.self, from: data)
        guard Set(journal.entries.map(\.target)).count == journal.entries.count else {
            throw InvalidJournal.invalidEntries
        }
        return journal
    }
}
