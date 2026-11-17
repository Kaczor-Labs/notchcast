import Foundation

enum LauncherNumberKeys {
    /// The row ⌘<digit> runs while a query is typed; nil leaves the stock favourite slot in charge.
    static func rowIndex(digit: Int, query: String, entryRows: [Int], enabled: Bool) -> Int? {
        guard enabled, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            (1...9).contains(digit), digit <= entryRows.count
        else { return nil }
        return entryRows[digit - 1]
    }

    /// The digit each row shows while ⌘ is held; the lowest digit wins a row two digits open.
    static func keycaps(rowFor: (Int) -> Int?) -> [Int: Character] {
        var caps: [Int: Character] = [:]
        for digit in (1...9).reversed() {
            if let row = rowFor(digit) { caps[row] = Character(String(digit)) }
        }
        return caps
    }
}
