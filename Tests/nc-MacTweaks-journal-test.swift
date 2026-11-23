// notchcast-sources: Tinycast/Features/Notchcast/MacTweaks/Model/*.swift
import Foundation

@main
struct MacTweaksJournalTest {
    static func main() throws {
        let pathBar = MacTweakTarget.preference(domain: "com.example.finder", key: "PathBar")
        let statusBar = MacTweakTarget.preference(domain: "com.example.finder", key: "StatusBar")
        let library = MacTweakTarget.libraryHidden
        let now = Date(timeIntervalSince1970: 100)
        let tweak = MacTweak(id: "path-bar", group: .finder, changes: [.preference(pathBar, .bool(true))])
        let unknown = MacTweak(id: "old-library-tweak", group: .finder, changes: [.showLibrary])

        let previous = MacTweakValue.dictionary(["setting": .array([.string("0"), .integer(0), .bool(false)])])
        let start: [MacTweakTarget: MacTweakValue] = [pathBar: previous, library: .bool(true)]
        var values = start
        var journal = MacTweakJournal()

        func apply(_ tweak: MacTweak, _ target: MacTweakTarget, _ value: MacTweakValue) {
            guard let next = journal.apply(tweak, target: target, value: value, current: values[target], now: now)
            else { preconditionFailure("Expected a change") }
            journal = next
            values[target] = value
            journal.finishWrite(target)
        }

        func restore(_ entry: MacTweakJournal.Entry) {
            if case .write(let value) = journal.restore(entry, current: values[entry.target]) {
                values[entry.target] = value
            }
            journal.forget(entry.target)
        }

        apply(tweak, pathBar, .bool(true))
        let unchanged = journal.apply(tweak, target: pathBar, value: .bool(true), current: values[pathBar], now: now)
        precondition(unchanged == nil)
        let prepared = journal.apply(tweak, target: pathBar, value: .integer(2), current: values[pathBar], now: now)!
        precondition(prepared.restore(prepared.entries[0], current: .bool(true)) == .write(previous))
        apply(tweak, pathBar, .integer(2))
        restore(journal.entries[0])
        precondition(values == start, "A second apply must keep the exact first value")

        apply(tweak, pathBar, .bool(true))
        values[pathBar] = .integer(1)
        restore(journal.entries[0])
        precondition(values[pathBar] == .integer(1), "Equivalent settings can still be different journal values")
        values = start

        apply(tweak, pathBar, .bool(true))
        apply(tweak, statusBar, .bool(true))
        apply(unknown, library, .bool(false))
        journal = try MacTweakJournal.decode(JSONEncoder().encode(journal))
        precondition(journal.restoreAll().first?.tweakID == unknown.id)
        for entry in journal.restoreAll() { restore(entry) }
        precondition(journal.entries.isEmpty && values == start)

        let removal = journal.apply(tweak, target: pathBar, value: nil, current: previous, now: now)!
        let reapply = removal.apply(tweak, target: pathBar, value: .bool(true), current: nil, now: now)!
        let pending = try MacTweakJournal.decode(JSONEncoder().encode(reapply))
        precondition(pending.restore(pending.entries[0], current: nil) == .write(previous))
        do {
            _ = try MacTweakJournal.decode(Data("invalid".utf8))
            preconditionFailure("Corrupt journals must be rejected")
        } catch is DecodingError {}

        precondition(MacTweakValue.bool(true).matches(.integer(1)))
        precondition(!MacTweakValue.bool(true).matches(.integer(2)))
        precondition(MacTweakValue.bool(false).matches(.string("NO")))
        precondition(!MacTweakValue.bool(false).matches(.string("other")))
        precondition(MacTweakValue.real(0.5).matches(.string("0.5")))
        print("Mac Tweaks journal passed")
    }
}
