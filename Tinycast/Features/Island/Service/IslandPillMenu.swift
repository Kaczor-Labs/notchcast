import AppKit
import SwiftUI

/// The resting pill's secondary-click menu: the stock menu panel hung below the pill.
@MainActor
final class IslandPillMenu: NSObject {
    private unowned let core: AppCore
    private let menu = MenuPanelController()
    private let state = IslandPillMenuState()
    private weak var observedPanel: MenuPanel?
    private var items: [PopoverMenuItem] = []
    private var corner: MenuPanelCorner?

    init(core: AppCore) {
        self.core = core
        super.init()
    }

    var isOpen: Bool { menu.isOpen }

    /// `pill` is measured from the top-left corner of `parent`, the island window.
    func toggle(below pill: CGRect, in parent: NSWindow) {
        if menu.isOpen {
            hide()
            return
        }
        core.palette.menuQuery = ""
        state.selection = 0
        let corner = MenuPanelCorner.belowControl(pill, trailing: false)
        self.corner = corner
        menu.show(content, corner: corner, parent: parent, core: core,
            onKeyDown: { [weak self] in self?.handleKey($0) ?? false },
            onDismiss: { [weak self] in self?.hide() })
        observeResign(in: parent)
    }

    private var content: AnyView {
        AnyView(IslandPillMenuView(state: state, items: { [weak self] in self?.visibleItems() ?? [] },
            activate: { [weak self] in self?.activate($0) }, filtered: { [weak self] in self?.refit() }))
    }

    /// Filtering or new add-on rows change the row count; the panel sizes only for new content.
    func refit() {
        guard let corner, menu.isOpen else { return }
        state.selection = 0
        state.revision += 1
        menu.update(content, corner: corner, core: core)
    }

    func hide() {
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        observedPanel = nil
        menu.hide()
        core.palette.menuQuery = ""
    }

    /// The stock panel hides the palette when its parent is not key, and the island never is.
    private func observeResign(in parent: NSWindow) {
        guard observedPanel == nil,
              let panel = parent.childWindows?.lazy.compactMap({ $0 as? MenuPanel }).first else { return }
        observedPanel = panel
        NotificationCenter.default.addObserver(self, selector: #selector(panelResignedKey),
            name: NSWindow.didResignKeyNotification, object: panel)
    }

    @objc private func panelResignedKey() { hide() }

    #if DEBUG
    var itemTitles: [String] { visibleItems().map(\.title) }
    /// What the open menu last rendered, without rebuilding it.
    var shownTitles: [String] { items.map(\.title) }
    var isObservingResign: Bool { observedPanel != nil }
    func activate(title: String) { visibleItems().firstIndex { $0.title == title }.map(activate) }
    #endif

    private func visibleItems() -> [PopoverMenuItem] {
        let settings = core.settings
        let meeting = core.island.glance.meeting
        let menus = (core.islandPresenter as? IslandPresenter)?.menus ?? []
        var sections = PillMenuRow.sections(clipboard: settings.clipboardEnabled,
            calendar: settings.calendarEnabled || meeting != nil, notes: settings.notesEnabled, carded: meeting != nil)
            .map { $0.map { item($0, meeting: meeting) } }
        // Add-on rows go above the two sections that always close the menu.
        sections.insert(addOnItems(menus), at: sections.count - 2)
        let query = ActionMenuSearchQuery(core.palette.menuQuery)
        var visible: [PopoverMenuItem] = []
        for section in sections {
            var matched = section.filter { query.score($0.title) != nil }
            if !visible.isEmpty, !matched.isEmpty { matched[0].startsSection = true }
            visible += matched
        }
        items = visible
        return visible
    }

    private func item(_ row: PillMenuRow, meeting: MeetingEvent?) -> PopoverMenuItem {
        let calendar = core.calendarCoordinator
        switch row {
        case .join:
            let provider = (meeting?.link?.provider ?? .generic).sfSymbol
            let title = MenuBarSummary.title(meeting?.title ?? "")
            return PopoverMenuItem(title: String(localized: "Join \(title)"), icon: .symbol(provider),
                detail: core.island.glance.current?.countdown) {
                if let meeting { calendar.join(meeting) }
            }
        case .openInCalendar:
            return PopoverMenuItem(title: String(localized: "Open in Calendar"), systemImage: "calendar") {
                if let meeting { calendar.openInCalendar(meeting) }
            }
        case .mySchedule:
            return command(.mySchedule) { calendar.showSchedule() }
        case .clipboardHistory:
            return command(.clipboardHistory) { [core] in core.paletteCoordinator.showPalette(mode: .clipboard) }
        case .showNotes:
            return command(.showNotes) { [core] in core.notesCoordinator.toggle() }
        case .createNote:
            return command(.createNote) { [core] in core.notesCoordinator.createNote() }
        case .searchNotes:
            return command(.searchNotes) { [core] in core.notesCoordinator.searchNotes() }
        case .checkForUpdates:
            return PopoverMenuItem(title: String(localized: "Check for Updates…"),
                systemImage: CommandID.checkForUpdates.sfSymbol) { [core] in core.updateCoordinator.checkForUpdates() }
        case .support:
            return PopoverMenuItem(title: String(localized: "Support \("Tinycast")…"),
                systemImage: CommandID.support.sfSymbol) { [core] in core.supportCoordinator.showSupport() }
        case .settings:
            return PopoverMenuItem(title: String(localized: "Settings…"), systemImage: CommandID.settings.sfSymbol,
                shortcut: "⌘,") { [core] in core.settingsCoordinator.showSettings() }
        case .quit:
            return PopoverMenuItem(title: CommandID.quit.name, systemImage: CommandID.quit.sfSymbol, shortcut: "⌘Q",
                isDestructive: true) { NSApp.terminate(nil) }
        }
    }

    /// The caller's own title, never localized; an unchecked column keeps it in line with the icons.
    private func addOnItems(_ menus: [IslandPresenter.Menu]) -> [PopoverMenuItem] {
        menus.flatMap { menu in
            menu.rows.map { row in
                var item = PopoverMenuItem(title: row.title, icon: .blank) { menu.onSelect(row.id) }
                item.isChecked = row.isChecked ?? false
                return item
            }
        }
    }

    private func command(_ id: CommandID, _ action: @escaping () -> Void) -> PopoverMenuItem {
        PopoverMenuItem(title: id.name, systemImage: id.sfSymbol, action: action)
    }

    private func activate(_ index: Int) {
        guard items.indices.contains(index), items[index].isSelectable else { return }
        let action = items[index].action
        hide()
        action()
    }

    private func move(_ step: Int) {
        guard !items.isEmpty else { return }
        state.selection = (state.selection + step + items.count) % items.count
    }

    /// Mirrors the palette's menu keys; ⌘, and ⌘Q work because no menu bar item carries them.
    private func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.charactersIgnoringModifiers == "\u{1B}" {
            if core.palette.menuQuery.isEmpty { hide() } else { core.palette.menuQuery = "" }
            return true
        }
        switch event.specialKey {
        case .some(.downArrow) where modifiers.isEmpty:
            move(1)
            return true
        case .some(.upArrow) where modifiers.isEmpty:
            move(-1)
            return true
        case .some(.carriageReturn), .some(.enter):
            activate(state.selection)
            return true
        default: break
        }
        let character = ASCIIKeyboardLayout.character(for: event)?.lowercased()
            ?? event.charactersIgnoringModifiers?.lowercased()
        switch (modifiers, character) {
        case ([.control], "n"): move(1)
        case ([.control], "p"): move(-1)
        case ([.command], ","): hide(); core.settingsCoordinator.showSettings()
        case ([.command], "q"): NSApp.terminate(nil)
        default: return false
        }
        return true
    }
}

@MainActor @Observable
private final class IslandPillMenuState {
    var selection = 0
    /// A swapped root view that looks the same is not redrawn; reading this forces the new rows.
    var revision = 0
}

private struct IslandPillMenuView: View {
    @Bindable var state: IslandPillMenuState
    let items: () -> [PopoverMenuItem]
    let activate: (Int) -> Void
    let filtered: () -> Void
    @Environment(PaletteState.self) private var palette

    var body: some View {
        let _ = state.revision
        PopoverMenu(header: Bundle.main.appDisplayName, items: items(), selection: $state.selection,
            visibleRows: Theme.Size.pillMenuVisibleRows, onActivate: activate,
            search: .init(placeholder: String(localized: "Search…"), placement: .top))
            .onChange(of: palette.menuQuery) { filtered() }
    }
}
