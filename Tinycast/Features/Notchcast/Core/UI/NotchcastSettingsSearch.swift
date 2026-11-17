import Foundation
import Synchronization

/// The Notchcast tabs' search rows: each shown tab, its island rows, then one per add-on switch.
enum NotchcastSettingsSearch {
    /// Installed by NotchcastCore before Settings can open; until then Island, which always shows.
    private static let switchRows = Mutex(rows([], commandWords: [:]))

    static var entries: [SettingsSearchEntry] { switchRows.withLock { $0 } }

    static let island = SettingsAnchor(tab: .notchcast(.island), title: LocalizedStringResource("Island", table: "Notchcast"))
    static let showsInCaptures = LocalizedStringResource("Show in screenshots and videos", table: "Notchcast")
    static let outlineWhenOpen = LocalizedStringResource("Outline when open", table: "Notchcast")
    static let position = LocalizedStringResource("Position on displays without a notch", table: "Notchcast")

    private static let islandRows = [
        SettingsSearchEntry(island, showsInCaptures, keywords: ["screen recording", "screen sharing", "capture", "hide"]),
        SettingsSearchEntry(island, outlineWhenOpen, keywords: ["keyline", "border", "line", "edge"]),
        SettingsSearchEntry(island, position, keywords: ["position", "notch", "menu bar", "top"])]

    static func anchor(_ category: NotchcastCategory) -> SettingsAnchor {
        SettingsAnchor(tab: .notchcast(.holding(category)), title: LocalizedStringResource(stringLiteral: category.title))
    }

    static func install(_ switches: [NotchcastSwitch], commandWords: [String: [String]]) {
        let rows = rows(switches, commandWords: commandWords)
        switchRows.withLock { $0 = rows }
    }

    /// Commands hide while their switch is off, so their words land on the switch row.
    private static func rows(_ switches: [NotchcastSwitch], commandWords: [String: [String]]) -> [SettingsSearchEntry] {
        NotchcastPane.shown(registered: Set(switches.map(\.category))).flatMap { pane in
            [SettingsSearchEntry(pane: .notchcast(pane), keywords: ["notchcast", pane == .island ? "notch" : "addons"])]
                + (pane == .island ? islandRows : [])
                + pane.categories.flatMap { category in
                    switches.filter { $0.category == category }.map { item in
                        SettingsSearchEntry(
                            anchor(category), LocalizedStringResource(stringLiteral: item.title),
                            keywords: [item.subtitle, item.id] + commandWords[item.id, default: []])
                    }
                }
        }
    }
}
