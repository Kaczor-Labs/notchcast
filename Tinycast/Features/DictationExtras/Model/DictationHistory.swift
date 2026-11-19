import Foundation

/// One finished dictation: what the model heard, what cleanup made of it, and where it went.
struct DictationHistoryEntry: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let raw: String
    let cleaned: String?
    let createdAt: Date
    let app: String?

    /// What was pasted, so Paste Again repeats it.
    var text: String { cleaned ?? raw }
}

/// The last dictations, newest first, capped so a lost paste can be recovered and no more.
struct DictationHistory: Equatable, Sendable {
    static let cap = 50

    private(set) var entries: [DictationHistoryEntry]

    init(entries: [DictationHistoryEntry] = []) {
        self.entries = Array(entries.sorted { $0.createdAt > $1.createdAt }.prefix(Self.cap))
    }

    /// False when there was nothing to keep: a blank raw transcript.
    @discardableResult
    mutating func record(
        raw: String, cleaned: String?, app: String?, at date: Date, id: UUID = UUID()
    ) -> Bool {
        let raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return false }
        let cleaned = cleaned?.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = DictationHistoryEntry(
            id: id, raw: raw, cleaned: cleaned?.isEmpty == false && cleaned != raw ? cleaned : nil,
            createdAt: date, app: app)
        entries.insert(entry, at: 0)
        if entries.count > Self.cap { entries.removeLast(entries.count - Self.cap) }
        return true
    }

    mutating func remove(_ id: DictationHistoryEntry.ID) {
        entries.removeAll { $0.id == id }
    }

    mutating func clear() {
        entries = []
    }

    func search(_ query: String) -> [DictationHistoryEntry] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }
        return entries.filter {
            $0.raw.localizedCaseInsensitiveContains(query)
                || $0.cleaned?.localizedCaseInsensitiveContains(query) == true
                || $0.app?.localizedCaseInsensitiveContains(query) == true
        }
    }
}
