import Foundation

extension LauncherScreen {
    /// The rows ⌘1–⌘9 count while a query is typed: every result, whatever its kind.
    var numberKeyRows: [Int] { LauncherNumberKeys.numberedRows(numberKeyRowKeys) }

    /// The ⌘-digit keycap of each result an add-on maps a digit to, keyed by its list row id.
    var numberKeySlots: [String: Character] {
        guard let digitRow = Self.digitRow else { return [:] }
        let keys = numberKeyRowKeys
        let rows = LauncherNumberKeys.numberedRows(keys)
        return LauncherNumberKeys.slots(keys: keys) { digitRow($0, vm.query, rows) }
    }

    /// `LauncherList`'s own row ids, which name a fallback by its entry rather than the fallback.
    private var numberKeyRowKeys: [String?] {
        rows.map { row in
            switch row {
            case .entry(let app): app.id
            case .file(let result): "file-" + result.id
            case .fallback(_, let entry): "fallback-" + entry.id
            case .calc, .meeting, .color: nil
            }
        }
    }
}
