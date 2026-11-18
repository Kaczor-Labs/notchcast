import Foundation

extension AppEntry {
    /// Keyed by the command's entry id, so its alias and hotkey are stored like a stock command's.
    init(notchcastCommand id: String, name: String, symbol: String, keywords: [String], owner: SettingsTab) {
        self.init(
            id: id, name: name, url: URL(string: "tinycast://" + id.replacingOccurrences(of: ":", with: "/"))!,
            bundleID: nil, kind: .command, settingsOwner: owner, symbolName: symbol, keywords: keywords)
        // Upstream draws a `.command` only from CommandID, so an add-on id would get its question mark.
        iconOverride = .tile(symbol: symbol, tint: owner.tint)
    }
}
