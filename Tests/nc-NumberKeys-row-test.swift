// notchcast-linux-ok
// notchcast-sources: Tinycast/Features/Notchcast/NumberKeys/Model/*.swift
import Foundation

@main
struct NumberKeysRowTest {
    static func main() {
        let rows = [1, 2, 4, 5, 6, 8, 9, 11, 12, 14, 15]
        for digit in 1...9 {
            precondition(LauncherNumberKeys.rowIndex(
                digit: digit, query: "a", entryRows: rows, enabled: true) == rows[digit - 1])
        }
        for digit in [-1, 0, 10, 11] {
            precondition(LauncherNumberKeys.rowIndex(
                digit: digit, query: "a", entryRows: rows, enabled: true) == nil)
        }
        for digit in 1...9 {
            let short = LauncherNumberKeys.rowIndex(digit: digit, query: "a", entryRows: [3, 7, 9], enabled: true)
            precondition(short == (digit <= 3 ? [3, 7, 9][digit - 1] : nil))
        }
        precondition(LauncherNumberKeys.rowIndex(digit: 1, query: "a", entryRows: [], enabled: true) == nil)
        for query in ["", " ", "  \n"] {
            for digit in 1...10 {
                precondition(LauncherNumberKeys.rowIndex(
                    digit: digit, query: query, entryRows: rows, enabled: true) == nil)
            }
        }
        for query in ["", "a"] {
            for digit in 1...10 {
                precondition(LauncherNumberKeys.rowIndex(
                    digit: digit, query: query, entryRows: rows, enabled: false) == nil)
            }
        }
        let caps = LauncherNumberKeys.keycaps { digit in
            LauncherNumberKeys.rowIndex(digit: digit, query: "a", entryRows: rows, enabled: true)
        }
        precondition(caps.count == 9, "nine results, nine keycaps")
        for digit in 1...9 { precondition(caps[rows[digit - 1]] == Character(String(digit)), "⌘\(digit)") }
        precondition(caps[rows[9]] == nil && caps[rows[10]] == nil, "the tenth result shows none")
        let few = LauncherNumberKeys.keycaps { LauncherNumberKeys.rowIndex(
            digit: $0, query: "a", entryRows: [3, 7], enabled: true) }
        precondition(few == [3: "1", 7: "2"], "only the rows a digit opens")
        for query in ["", "a"] {
            let none = LauncherNumberKeys.keycaps { LauncherNumberKeys.rowIndex(
                digit: $0, query: query, entryRows: rows, enabled: query.isEmpty) }
            precondition(none.isEmpty, "no query or switched off: favourites keep their own keycaps")
        }
        precondition(LauncherNumberKeys.keycaps { _ in 5 } == [5: "1"], "a shared row shows its lowest digit")
        // #869: a file, a fallback and an entry each take a digit; only a lead card is skipped.
        let keys: [String?] = [nil, "file-/f.txt", "fallback-web", "com.app"]
        let numbered = LauncherNumberKeys.numberedRows(keys)
        precondition(numbered == [1, 2, 3], "every result row is numbered, the calculator card is not")
        let slots = LauncherNumberKeys.slots(keys: keys) {
            LauncherNumberKeys.rowIndex(digit: $0, query: "f", entryRows: numbered, enabled: true)
        }
        precondition(slots == ["file-/f.txt": "1", "fallback-web": "2", "com.app": "3"], "file and fallback show keycaps")
        precondition(LauncherNumberKeys.rowIndex(digit: 1, query: "f", entryRows: numbered, enabled: true) == 1,
                     "⌘1 opens the file row, never an empty favourite slot")
        print("nc-NumberKeys-row-test: ok")
    }
}
