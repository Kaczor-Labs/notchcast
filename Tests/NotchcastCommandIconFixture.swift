import AppKit
import SwiftUI

/// #909: a command draws its own symbol as a tile in its owner tab's tint; run per add-on (#949).
@MainActor
enum NotchcastCommandIconCheck {
    static var failures = 0
    static var checks = 0

    static func check(_ name: String, _ value: Bool) {
        checks += 1
        if !value { failures += 1; print("FAIL \(name)") }
    }

    static func run(_ addon: any NotchcastAddon.Type) {
        let domain = "tinycast.notchcast-command-icons-test.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let index = AppIndex(
            ranking: LauncherRankingStore(
                fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(domain).json")),
            aliases: AliasStore(defaults: defaults))
        let switches = Dictionary(addon.switches.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let panes = addon.commands.map { switches[$0.switchID].map { NotchcastPane.holding($0.category) } ?? .island }
        let owners = Dictionary(zip(addon.commands.map(\.id), panes.map { SettingsTab.notchcast($0) }),
                                uniquingKeysWith: { a, _ in a })
        // Built exactly as NotchcastCore's onCommandsChanged builds them.
        index.extraCommandEntries = addon.commands.map {
            AppEntry(notchcastCommand: $0.id, name: $0.name, symbol: $0.symbol, keywords: $0.keywords, owner: owners[$0.id]!)
        }
        check("\(addon) declares commands to walk", !addon.commands.isEmpty)
        for command in addon.commands {
            guard let entry = index.apps.first(where: { $0.id == command.id }) else {
                check("\(command.id) reaches the launcher index", false)
                continue
            }
            let icon = entry.iconSource
            check("\(command.id) does not draw the question mark (\(icon))", icon != .symbol("questionmark"))
            guard case .tile(let symbol, let tint) = icon else {
                check("\(command.id) draws a tile like stock commands (\(icon))", false)
                continue
            }
            check("\(command.id) draws its own symbol \(command.symbol), got \(symbol)", symbol == command.symbol)
            check("\(command.id)'s symbol \(symbol) is a real SF Symbol",
                  NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil)
            check("\(command.id) is tinted like its owner tab, got \(tint)", tint == owners[command.id]?.tint)
        }
        print("\(checks) \(addon) command icon checks; \(failures) failures")
        if failures > 0 { exit(1) }
        print("PASSED")
    }
}

// Empty feature catalogs keep this harness on the launcher index; AppInstallationTests stubs the same.
enum ExtensionRefreshState: Hashable, Sendable { case idle }
enum CommandID: String, CaseIterable, Sendable {
    case fixture
    var name: String { rawValue }
    var sfSymbol: String { "" }
    var tint: IconTint { .gray }
    var hotKeyAction: HotKeyAction? { nil }
    var isQueryDriven: Bool { false }
    var suggestionPriority: Int? { nil }
    var boostedTerms: Set<String> { [] }
    var owner: SettingsTab? { nil }
}
enum CommandCatalog {
    static let all: [AppEntry] = []
    // Upstream's own lookup: an add-on command's id is never a CommandID.
    static func command(for entry: AppEntry) -> CommandID? { CommandID(rawValue: entry.id) }
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
    var tint = IconTint.gray
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
