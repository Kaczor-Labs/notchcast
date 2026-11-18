// notchcast-sources: Tinycast/Features/Launcher/Model/SearchRelevance.swift Tinycast/Features/Launcher/Model/ScriptRomanization.swift Tinycast/Features/Launcher/Model/LauncherMatch.swift
// notchcast-sources: Tinycast/Features/Launcher/Model/EntryNaming.swift Tinycast/Features/Launcher/Model/LauncherOrder.swift Tinycast/Features/Launcher/Model/LauncherRankingStore.swift
// notchcast-sources: Tinycast/Features/Launcher/Model/LauncherSuggestions.swift Tinycast/Features/Launcher/Model/SearchScopes.swift Tinycast/Features/Launcher/Service/AppIndex.swift
// notchcast-sources: Tinycast/Features/Launcher/Service/AppLauncher.swift Tinycast/Features/Launcher/Service/RunningAppsMonitor.swift Tinycast/Features/Launcher/Service/FavoritesStore.swift
// notchcast-sources: Tinycast/Features/FileSearch/Model/FileSearchResult.swift Tinycast/Features/Launcher/Service/AliasStore.swift
// notchcast-sources: Tinycast/Features/Launcher/Service/VisibilityStore.swift Tinycast/Features/Launcher/Service/BundleNameCache.swift
// notchcast-sources: Tinycast/Platform/AppDisplayName.swift Tinycast/Platform/BundleLocalization.swift
// notchcast-sources: Tinycast/Platform/SystemLanguages.swift Tinycast/Platform/Images/FileIconStamp.swift
// notchcast-sources: Tinycast/Platform/Memo.swift Tinycast/Platform/Signposts.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift Tinycast/Platform/LocalizedResource.swift
// notchcast-sources: Tinycast/Features/Notchcast/NotchcastCommandEntry.swift
// notchcast-sources: Tinycast/Features/Notchcast/NotchcastLauncherHides.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/NotchcastSwitch.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/NotchcastCategory.swift
// notchcast-sources: Tinycast/Features/HotKeys/Model/HotKeyAction.swift
// notchcast-sources: Tinycast/Features/HotKeys/Model/HotKeyAction+EntryID.swift
// notchcast-sources: Tinycast/Features/HotKeys/Model/DoubleTapModifier.swift Tinycast/Features/HotKeys/Model/ModifierKey.swift
// notchcast-sources: Tinycast/Features/HotKeys/Model/HotKeyBinding.swift Tinycast/Features/HotKeys/Model/HyperKey.swift
// notchcast-sources: Tinycast/Features/HotKeys/Model/HIDKeyMapping.swift Tinycast/Features/HotKeys/Service/KeyShortcut.swift
// notchcast-sources: Tinycast/Features/HotKeys/Service/HotKeyManager.swift Tinycast/Platform/ASCIIKeyboardLayout.swift
import AppKit
import Carbon.HIToolbox
import Observation

/// Two shipped add-on commands take an alias, a hotkey and their own launcher switch, Commands off.
@main
@MainActor
enum NotchcastCommandAliasTests {
    static var failures = 0
    static var checks = 0

    static func check(_ name: String, _ value: Bool) {
        checks += 1
        if !value { failures += 1; print("FAIL \(name)") }
    }

    static func main() async {
        let domain = "tinycast.notchcast-command-alias-test.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let aliases = AliasStore(defaults: defaults)
        let ranking = LauncherRankingStore(
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(domain).json"))
        let index = AppIndex(ranking: ranking, aliases: aliases)
        let commands = [
            ("command:nc-generate-password", "Generate Password", "zq", ["random", "secure"]),
            ("command:nc-screenshot-area", "Capture Area", "xj", []),
        ]
        index.extraCommandEntries = commands.map {
            AppEntry(notchcastCommand: $0.0, name: $0.1, symbol: "key", keywords: $0.3, owner: .addonTab)
        }
        for (id, name, alias, _) in commands {
            let entry = index.apps.first { $0.id == id }
            check("\(name) is owned by its add-on tab, which draws its alias and hotkey fields",
                  entry?.kind == .command && entry?.settingsOwner == .addonTab)
            check("\(name) keys its alias by its entry id", entry?.preferenceKey == id)
            check("\(name) is not found by its alias before one is set", index.matches(alias).first?.id != id)
            aliases.setAlias(alias, for: id)
            check("\(name) is the top launcher match for its alias", index.matches(alias).first?.id == id)
            check("\(name)'s alias survives a relaunch", AliasStore(defaults: defaults).alias(for: id) == alias)
        }
        hotKeys(index.apps.filter { $0.id.hasPrefix("command:nc-") }, defaults: defaults)
        stockCommandsOff(index.apps.filter { $0.id.hasPrefix("command:nc-") }, defaults: defaults)
        await launcherToggle(commands.map { ($0.0, $0.1, $0.2) })
        print("\(checks) add-on command alias checks; \(failures) failures")
        if failures > 0 { exit(1) }
        print("PASSED")
    }

    /// #868: a command's own "Show in launcher" alone decides whether the launcher finds it.
    static func launcherToggle(_ commands: [(id: String, name: String, alias: String)]) async {
        let domain = "tinycast.notchcast-launcher-toggle-test.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let aliases = AliasStore(defaults: defaults)
        let index = AppIndex(
            ranking: LauncherRankingStore(
                fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(domain).json")),
            aliases: aliases)
        let visibility = VisibilityStore(defaults: defaults)
        let favorites = FavoritesStore(defaults: defaults)
        let hotKeys = HotKeyManager(defaults: defaults)
        // The maintainer's Mac: an earlier version hid both commands, and stock Commands is off.
        visibility.replace(hiddenItems: commands.map(\.id), disabledKinds: ["command"])
        let preferences = NotchcastPreferences(defaults: defaults, switches: [])
        let hides = NotchcastLauncherHides(
            visibility: visibility, preferences: preferences, commandIDs: Set(commands.map(\.id)))
        func publish() {
            index.extraCommandEntries = commands.filter { preferences.showsInLauncher($0.id) }.map {
                AppEntry(notchcastCommand: $0.id, name: $0.name, symbol: "key", keywords: [], owner: .addonTab)
            }
        }
        func found(_ query: String, _ id: String) -> Bool {
            index.orderedResults(query: query, visibility: visibility, favorites: favorites, hotKeys: hotKeys)
                .entries.first?.id == id
        }
        publish()
        for command in commands {
            aliases.setAlias(command.alias, for: command.id)
            check("\(command.name) shows in launcher by default", preferences.showsInLauncher(command.id))
            check("\(command.name) is found by name despite an earlier stock hide", found(command.name, command.id))
            check("\(command.name) is found by alias despite an earlier stock hide", found(command.alias, command.id))
            preferences.setShowsInLauncher(command.id, false)
            publish()
            check("\(command.name) off is not found by name", !found(command.name, command.id))
            check("\(command.name) off is not found by alias", !found(command.alias, command.id))
            check("\(command.name) off survives a relaunch",
                  !NotchcastPreferences(defaults: defaults, switches: []).showsInLauncher(command.id))
            preferences.setShowsInLauncher(command.id, true)
            publish()
            check("\(command.name) back on is found by alias", found(command.alias, command.id))
        }
        let first = index.apps.first { $0.id == commands[0].id }!
        visibility.setItemVisible(false, for: first)
        await hides.adoption?.value
        check("the launcher's Hide turns the command's own switch off", !preferences.showsInLauncher(first.id))
        check("the launcher's Hide leaves no stock hide behind", visibility.isItemVisible(first))
    }

    /// The stock Commands switch gates stock commands only; Capture Area must survive it being off.
    static func stockCommandsOff(_ entries: [AppEntry], defaults: UserDefaults) {
        let visibility = VisibilityStore(defaults: defaults)
        visibility.setKindEnabled(false, for: .command)
        check("both shipped commands are checked with Commands off", entries.count == 2)
        for entry in entries {
            check("\(entry.name) stays in the launcher with Commands off", visibility.isVisible(entry))
            check("\(entry.name)'s hotkey still fires with Commands off",
                  entry.hotKeyAction.map { visibility.allowsHotKey($0) } == true)
        }
    }

    /// The shortcut recorder binds whatever `AppEntry.hotKeyAction` returns, so that action must fire.
    static func hotKeys(_ entries: [AppEntry], defaults: UserDefaults) {
        let ids = ["command:nc-generate-password", "command:nc-screenshot-area"]
        check("both shipped commands are launcher rows", entries.map(\.id).sorted() == ids)
        let actions = entries.compactMap(\.hotKeyAction)
        for (entry, action) in zip(entries, actions) {
            check("\(entry.id) gets the entry-ID mapping's action",
                  action == .notchcastCommand(entryID: entry.id) && HotKeyAction(entryID: entry.id) == action)
            check("\(entry.id) is stored under its stock-shaped key", action.defaultsKey == "hotkey." + entry.id)
        }
        let manager = HotKeyManager(defaults: defaults)
        manager.extraActions = actions
        for (action, key) in zip(actions, [kVK_ANSI_1, kVK_ANSI_2]) {
            manager.setBinding(.combo(KeyShortcut(carbonKeyCode: key, carbonModifiers: controlKey | optionKey)),
                               for: action)
        }
        let relaunched = HotKeyManager(defaults: defaults)
        var ran: [String] = []
        relaunched.onRunNotchcastCommand = { ran.append($0) }
        relaunched.extraActions = actions
        let center = HotKeyCenter.current
        for action in actions { center?.entries[action.defaultsKey]?.onKeyDown(0) }
        check("both entries' chords reload and run exactly their commands", actions.count == 2 && ran == entries.map(\.id))
    }
}

// Empty feature catalogs keep this harness on the launcher index; AppInstallationTests stubs the same.
enum SettingsTab: Sendable { case ai, addonTab }
enum ExtensionRefreshState: Hashable, Sendable { case idle }
enum EntryIcon: Hashable, Sendable { case file(stamp: Int), symbol(String) }
enum IconCache {
    static func observeStyle() {}
    static func icon(for source: EntryIcon, fileURL: URL) -> NSImage { NSImage() }
}
enum CommandID: String, CaseIterable, Sendable {
    case fixture
    var name: String { rawValue }
    var sfSymbol: String { "" }
    var hotKeyAction: HotKeyAction? { nil }
    var isQueryDriven: Bool { false }
    var suggestionPriority: Int? { nil }
    var boostedTerms: Set<String> { [] }
    var owner: SettingsTab? { nil }
}
enum CommandCatalog {
    static let all: [AppEntry] = []
    static func command(for entry: AppEntry) -> CommandID? { nil }
}
struct OtherEntry<Tag: Sendable>: Sendable {
    var id = UUID()
    var entryID: String { id.uuidString }
    var name = ""
    var iconSymbol: String?
    var isEnabled = true
    var showsInRootSearch = true
    var link = ""
    static var sfSymbol: String { "" }
    static var entryIDPrefix: String { "" }
    static func id(fromEntryID id: String) -> UUID? { nil }
    static func entryID(for id: UUID) -> String { "" }
    static func precedes(_ lhs: Self, _ rhs: Self) -> Bool { lhs.name < rhs.name }
}
enum LayoutTag: Sendable {}
enum RoomTag: Sendable {}
enum SizeTag: Sendable {}
enum QuickActionTag: Sendable {}
enum CommandTag: Sendable {}
enum QuicklinkTag: Sendable {}
enum ShortcutTag: Sendable {}
typealias WindowLayout = OtherEntry<LayoutTag>
typealias Room = OtherEntry<RoomTag>
typealias CustomWindowSize = OtherEntry<SizeTag>
typealias CustomQuickAction = OtherEntry<QuickActionTag>
typealias CustomCommand = OtherEntry<CommandTag>
typealias Quicklink = OtherEntry<QuicklinkTag>
typealias AppleShortcut = OtherEntry<ShortcutTag>
struct SystemAction: Sendable {
    enum ID: String, CaseIterable, Sendable { case fixture }
    var id = ID.fixture
    var entryID = ""
    var name = ""
    var englishName = ""
    var sfSymbol = ""
}
enum SystemActionCatalog {
    static let all: [SystemAction] = []
    static func action(forEntryID id: String) -> SystemAction? { nil }
    static func action(id: SystemAction.ID) -> SystemAction { SystemAction() }
}
struct WindowCommand: Sendable {
    enum ID: String, CaseIterable, Sendable { case fixture }
    var id = ID.fixture
    var entryID = ""
    var name = ""
    var englishName = ""
    var sfSymbol = ""
}
enum WindowCommandCatalog {
    static let all: [WindowCommand] = []
    static func command(forEntryID id: String) -> WindowCommand? { nil }
    static func command(id: WindowCommand.ID) -> WindowCommand? { nil }
}
enum QuicklinkDestination {
    static func detect(_ link: String) -> Self? { nil }
    var defaultSymbol: String { "" }
}
struct StoredSnippet {
    typealias ID = String
    static let entryIDPrefix = ""
    struct Snippet { var isEnabled = true; var name = ""; var keyword: String? }
    var snippet = Snippet()
    var entryID = ""
    var fileURL = URL(fileURLWithPath: "/")
    static let sfSymbol = ""
    static func id(fromEntryID id: String) -> ID? { nil }
}
enum SettingsPaneScanner {
    struct Cache: Sendable {}
    static func scan(languages: [String], cache: Cache?) -> ([AppEntry], Cache?) { ([], nil) }
}
@Observable
final class AppSettings {
    var searchScopes: [String] = []
    var launcherShowsSuggestions = true
    var rootSearchSensitivity = SearchSensitivity.default
}
@MainActor
final class ModifierTapMonitor {
    var isPaused = false
    var onTrigger: ((HotKeyBinding) -> Void)?
    var onHoldPressed: (() -> Void)?
    var onHoldReleased: (() -> Void)?
    var onHoldCancelled: (() -> Void)?
    func start() {}
    func update(bound: Set<HotKeyBinding>, holdKey: ModifierKey?) {}
}
@MainActor
final class ShortcutCaptureSession {
    func start(action: HotKeyAction, hotKeys: HotKeyManager) {}
    func stop() {}
}
/// Records registrations instead of installing them, so no real hotkey exists during the run.
@MainActor
final class HotKeyCenter {
    struct Entry {
        let shortcut: KeyShortcut
        let onKeyDown: (UInt64) -> Void
        let onKeyUp: (() -> Void)?
    }
    static weak var current: HotKeyCenter?
    var entries: [String: Entry] = [:]
    var isPaused = false
    init() { Self.current = self }
    func register(
        id: String, shortcut: KeyShortcut, onKeyDown: @escaping (UInt64) -> Void, onKeyUp: (() -> Void)? = nil
    ) {
        entries[id] = Entry(shortcut: shortcut, onKeyDown: onKeyDown, onKeyUp: onKeyUp)
    }
    func unregister(id: String) { entries[id] = nil }
}
