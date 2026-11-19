import Foundation
import Observation

/// A JSON file in this build's own Application Support folder; no backup or sync carries it.
@MainActor
@Observable
final class DictationHistoryStore {
    private let fileURL: URL
    private(set) var history: DictationHistory

    init(fileURL: URL = AppPaths.applicationSupport().appending(path: "dictation-history.json")) {
        self.fileURL = fileURL
        let entries = (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONDecoder().decode([DictationHistoryEntry].self, from: $0) }
        history = DictationHistory(entries: entries ?? [])
    }

    var entries: [DictationHistoryEntry] { history.entries }

    func record(raw: String, cleaned: String?, app: String?, at date: Date) {
        guard history.record(raw: raw, cleaned: cleaned, app: app, at: date) else { return }
        persist()
    }

    func remove(_ entry: DictationHistoryEntry) {
        history.remove(entry.id)
        persist()
    }

    /// Deletes the file too, so switching history off leaves nothing on disk.
    func clear() {
        history.clear()
        try? FileManager.default.removeItem(at: fileURL)
    }

    func search(_ query: String) -> [DictationHistoryEntry] {
        history.search(query)
    }

    private func persist() {
        guard !history.entries.isEmpty else {
            clear()
            return
        }
        guard let data = try? JSONEncoder().encode(history.entries) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: [.atomic])
    }
}
