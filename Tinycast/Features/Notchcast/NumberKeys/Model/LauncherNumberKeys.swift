import Foundation

enum LauncherNumberKeys {
    /// The row ⌘<digit> runs while a query is typed; nil leaves the stock favourite slot in charge.
    static func rowIndex(digit: Int, query: String, entryRows: [Int], enabled: Bool) -> Int? {
        guard enabled, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            (1...9).contains(digit), digit <= entryRows.count
        else { return nil }
        return entryRows[digit - 1]
    }
}
