import Foundation
import Synchronization

/// The Notchcast pane's search rows: the pane, then one row per add-on switch under its category.
enum NotchcastSettingsSearch {
    /// Installed by NotchcastCore before Settings can open; the catalog reads it once.
    private static let switchRows = Mutex<[SettingsSearchEntry]>([])

    static var entries: [SettingsSearchEntry] {
        [.init(pane: .notchcast, keywords: ["island", "addons"]),
         .init(island, showsInCaptures, keywords: ["screen recording", "screen sharing", "capture", "hide"])]
            + switchRows.withLock { $0 }
    }

    static let island = SettingsAnchor(tab: .notchcast, title: LocalizedStringResource("Island", table: "Notchcast"))
    static let showsInCaptures = LocalizedStringResource("Show in screenshots and videos", table: "Notchcast")

    static func anchor(_ category: NotchcastCategory) -> SettingsAnchor {
        SettingsAnchor(tab: .notchcast, title: LocalizedStringResource(stringLiteral: category.title))
    }

    /// Commands hide while their switch is off, so their words land on the switch row.
    static func install(_ switches: [NotchcastSwitch], commandWords: [String: [String]]) {
        let rows = NotchcastCategory.allCases.flatMap { category in
            switches.filter { $0.category == category }.map { item in
                SettingsSearchEntry(
                    anchor(category), LocalizedStringResource(stringLiteral: item.title),
                    keywords: [item.subtitle, item.id] + commandWords[item.id, default: []])
            }
        }
        switchRows.withLock { $0 = rows }
    }
}
