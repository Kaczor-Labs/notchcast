import Foundation
import Synchronization

/// The Notchcast tabs' search rows: each shown tab, its island rows, then the listed switches.
enum NotchcastSettingsSearch {
    /// Installed by NotchcastCore before Settings can open; until then Island, which always shows.
    private static let switchRows = Mutex(rows([], commandWords: [:], optionWords: [:]))

    static var entries: [SettingsSearchEntry] { switchRows.withLock { $0 } }

    static let island = SettingsAnchor(tab: .notchcast(.island), title: LocalizedStringResource("Island", table: "Notchcast"))
    static let showsInCaptures = LocalizedStringResource("Show in screenshots and videos", table: "Notchcast")
    static let outlineWhenOpen = LocalizedStringResource("Outline when open", table: "Notchcast")
    static let opensOnHover = LocalizedStringResource("Open on hover", table: "Notchcast")
    static let position = LocalizedStringResource("Position on displays without a notch", table: "Notchcast")
    static let lookTitle = LocalizedStringResource("Look", table: "Notchcast")
    static let look = SettingsAnchor(tab: .notchcast(.island), title: lookTitle)

    private static let islandRows = [
        SettingsSearchEntry(island, showsInCaptures, keywords: ["screen recording", "screen sharing", "capture", "hide"]),
        SettingsSearchEntry(island, outlineWhenOpen, keywords: ["keyline", "border", "line", "edge"]),
        SettingsSearchEntry(island, opensOnHover, keywords: ["hover", "pointer", "mouse", "expand"]),
        SettingsSearchEntry(island, position, keywords: ["position", "notch", "menu bar", "top"]),
        SettingsSearchEntry(group: look, lookTitle, keywords: ["frosted", "glass", "black", "blur", "display", "monitor"])]

    /// Notchcast › Dictation: a child row's words ride on its section's main switch.
    private static let dictationRows = [
        SettingsSearchEntry(
            .notchcastDictation, LocalizedStringResource("Enable dictation", table: "Notchcast"),
            keywords: ["speech", "voice", "transcription", "microphone", "globe", "fn", "shortcut",
                       "Shortcut behavior", "hold to talk", "push to talk", "Play sounds", "sound", "chime",
                       "model", "parakeet", "ultra", "download"]),
        SettingsSearchEntry(
            .dictationCleanup, LocalizedStringResource("Clean up text", table: "Notchcast"),
            keywords: ["ai", "punctuation", "filler", "claude", "codex",
                       String(localized: "Cleanup model", table: "Notchcast"),
                       String(localized: "Cleanup prompt", table: "Notchcast"),
                       "reasoning effort", String(localized: "AI providers", table: "Notchcast"),
                       "api key", "openai", "anthropic", "openrouter", "apple intelligence"]),
        SettingsSearchEntry(
            .dictationHistory, LocalizedStringResource("Keep dictation history", table: "Notchcast"),
            keywords: ["recover", "lost", "Dictation History"]),
        SettingsSearchEntry(
            group: .dictationSharing,
            LocalizedStringResource("Share the dictation model with other apps", table: "Notchcast"),
            keywords: ["share", "sharing", "endpoint", "port", "token", "whisper", "transcriptions"])]

    static func anchor(_ category: NotchcastCategory) -> SettingsAnchor {
        SettingsAnchor(tab: .notchcast(.holding(category)), title: LocalizedStringResource(stringLiteral: category.title))
    }

    static func install(
        _ switches: [NotchcastSwitch], commandWords: [String: [String]], optionWords: [String: [String]] = [:]
    ) {
        let rows = rows(switches, commandWords: commandWords, optionWords: optionWords)
        switchRows.withLock { $0 = rows }
    }

    private static func rows(
        _ switches: [NotchcastSwitch], commandWords: [String: [String]], optionWords: [String: [String]]
    ) -> [SettingsSearchEntry] {
        let layout = NotchcastSettingsLayout(switches: switches)
        var wordsByOwner: [String: [String]] = [:]
        for item in switches {
            var words = [item.title, item.subtitle, item.id] + commandWords[item.id, default: []]
            words += optionWords[item.id, default: []]
            words += item.searchTerms
            if item.requiredGrants.contains(.accessibility) {
                words.append(String(localized: "Needs Accessibility access", table: "Notchcast"))
            }
            for owner in layout.listedOwners(of: item) {
                wordsByOwner[owner, default: []].append(contentsOf: words)
            }
        }
        let listed = switches.filter { $0.dependencies.isEmpty && $0.listedWhenAnyEnabled.isEmpty }
        return NotchcastPane.shown(registered: Set(listed.map(\.category))).flatMap { pane in
            [SettingsSearchEntry(pane: .notchcast(pane), keywords: ["notchcast"] + paneWords(pane))]
                + (pane == .island ? islandRows : pane == .dictation ? dictationRows : [])
                + pane.categories.flatMap { category in
                    listed.filter { $0.category == category }.map { item in
                        SettingsSearchEntry(
                            anchor(category), LocalizedStringResource(stringLiteral: item.title),
                            keywords: wordsByOwner[item.id, default: []])
                    }
                }
        }
    }

    private static func paneWords(_ pane: NotchcastPane) -> [String] {
        switch pane {
        case .island: ["notch"]
        case .dictation: ["speech", "voice", "transcription", "microphone"]
        default: ["addons"]
        }
    }
}

/// The Dictation tab's sections; Cleanup and History keep the names their rows were built with.
extension SettingsAnchor {
    static let notchcastDictation = Self(tab: .notchcast(.dictation), title: "Dictation")
    static let notchcastDictationShortcut = Self(tab: .notchcast(.dictation), title: "Shortcut")
    static let notchcastDictationModel = Self(tab: .notchcast(.dictation), title: "Model")
    static let dictationCleanup = Self(
        tab: .notchcast(.dictation), title: LocalizedStringResource("Cleanup", table: "Notchcast"))
    static let dictationHistory = Self(tab: .notchcast(.dictation), title: "History")
    static let dictationSharing = Self(
        tab: .notchcast(.dictation), title: LocalizedStringResource("Sharing", table: "Notchcast"))
}
