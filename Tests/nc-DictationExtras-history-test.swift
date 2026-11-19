// notchcast-sources: Tinycast/Features/DictationExtras/Model/DictationHistory.swift
// notchcast-sources: Tinycast/Features/DictationExtras/Service/DictationHistoryStore.swift
// notchcast-sources: Tinycast/Platform/AppPaths.swift

import Foundation

func check(_ condition: Bool, _ message: String) {
    guard condition else { fatalError("nc-DictationExtras-history-test: \(message)") }
}

let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

func at(_ minute: Int) -> Date { start.addingTimeInterval(Double(minute) * 60) }

@main
@MainActor
enum DictationExtrasHistoryTests {
    static func main() {
        // Recording: newest first, blanks ignored, an unchanged cleanup kept as raw only.
        var history = DictationHistory()
        check(!history.record(raw: " \n", cleaned: "x", app: nil, at: at(0)), "a blank raw is not kept")
        check(history.record(raw: " hello ", cleaned: "Hello.", app: "Notes", at: at(1)), "kept")
        history.record(raw: "same", cleaned: " same ", app: nil, at: at(2))
        history.record(raw: "raw", cleaned: "  ", app: nil, at: at(3))
        check(history.entries.map(\.raw) == ["raw", "same", "hello"], "newest first, trimmed")
        check(
            history.entries[2].cleaned == "Hello." && history.entries[2].text == "Hello.", "cleaned is pasted"
        )
        check(history.entries[1].cleaned == nil, "a cleanup equal to raw is dropped")
        check(
            history.entries[0].cleaned == nil && history.entries[0].text == "raw",
            "an empty cleanup is dropped")

        // Search covers raw, cleaned and app; a blank query lists everything.
        check(history.search("HELLO.").map(\.raw) == ["hello"], "cleaned text matches")
        check(history.search("notes").map(\.raw) == ["hello"], "the app matches")
        check(history.search("  ").count == 3, "a blank query lists all")
        check(history.search("nothing").isEmpty, "no match is empty")

        let id = history.entries[1].id
        history.remove(id)
        check(!history.entries.contains { $0.id == id }, "remove drops one entry")

        // The cap keeps the newest 50, on record and on load.
        var full = DictationHistory()
        for minute in 0..<60 { full.record(raw: "d\(minute)", cleaned: nil, app: nil, at: at(minute)) }
        check(full.entries.count == DictationHistory.cap && DictationHistory.cap == 50, "capped at 50")
        check(full.entries.first?.raw == "d59" && full.entries.last?.raw == "d10", "the oldest go first")
        let loaded = DictationHistory(entries: full.entries.reversed())
        check(loaded.entries.first?.raw == "d59", "loading sorts newest first")

        // The store persists to its file and clearing deletes the file.
        let folder = FileManager.default.temporaryDirectory.appending(
            path: "nc-dictation-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "dictation-history.json")
        let store = DictationHistoryStore(fileURL: file)
        check(store.entries.isEmpty && !FileManager.default.fileExists(atPath: file.path), "starts empty")
        store.record(raw: "one", cleaned: "One.", app: "Mail", at: at(1))
        store.record(raw: "two", cleaned: nil, app: nil, at: at(2))
        check(FileManager.default.fileExists(atPath: file.path), "recording writes the file")
        let reopened = DictationHistoryStore(fileURL: file)
        check(reopened.entries == store.entries, "a new store reads the same entries")
        check(reopened.search("mail").map(\.raw) == ["one"], "the store searches")
        reopened.remove(reopened.entries[0])
        check(DictationHistoryStore(fileURL: file).entries.map(\.raw) == ["one"], "remove persists")
        reopened.remove(reopened.entries[0])
        check(!FileManager.default.fileExists(atPath: file.path), "removing the last entry deletes the file")
        store.clear()
        check(store.entries.isEmpty, "clear empties the store")
        store.record(raw: "three", cleaned: nil, app: nil, at: at(3))
        store.clear()
        check(!FileManager.default.fileExists(atPath: file.path), "clear deletes the file")
        check(
            AppPaths.applicationSupport(bundleID: "app.notchcast.dev").path.hasSuffix("app.notchcast.dev"),
            "the default file sits in this channel's folder")

        print("nc-DictationExtras-history-test: all passed")
    }
}
