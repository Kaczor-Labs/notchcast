import AppKit
import SwiftUI

/// The resting pill's secondary-click menu: the stock menu panel hung below the pill.
@MainActor
final class IslandPillMenu {
    private unowned let core: AppCore
    private let menu = MenuPanelController()
    private let state = IslandPillMenuState()
    private var resignObserver: NSObjectProtocol?
    private var items: [PopoverMenuItem] = []
    private var corner: MenuPanelCorner?

    init(core: AppCore) { self.core = core }

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

    /// Filtering changes the row count, and the panel sizes itself only when given new content.
    private func refit() {
        guard let corner, menu.isOpen else { return }
        state.selection = 0
        menu.update(content, corner: corner, core: core)
    }

    func hide() {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        menu.hide()
        core.palette.menuQuery = ""
    }

    /// The stock panel hides the palette when its parent is not key, and the island never is.
    private func observeResign(in parent: NSWindow) {
        guard resignObserver == nil, let panel = parent.childWindows?.first(where: { $0 is MenuPanel }) else { return }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    #if DEBUG
    var itemTitles: [String] { visibleItems().map(\.title) }
    #endif

    private func visibleItems() -> [PopoverMenuItem] {
        let settings = core.settings
        let meeting = core.island.glance.meeting
        let sections = PillMenuRow.sections(clipboard: settings.clipboardEnabled,
            calendar: settings.calendarEnabled || meeting != nil, notes: settings.notesEnabled, carded: meeting != nil)
        let query = ActionMenuSearchQuery(core.palette.menuQuery)
        var visible: [PopoverMenuItem] = []
        for section in sections {
            var matched = section.map { item($0, meeting: meeting) }.filter { query.score($0.title) != nil }
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

    /// Mirrors the palette's menu keys; ⌘, and ⌘Q work here because no menu bar item carries them.
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
}

private struct IslandPillMenuView: View {
    @Bindable var state: IslandPillMenuState
    let items: () -> [PopoverMenuItem]
    let activate: (Int) -> Void
    let filtered: () -> Void
    @Environment(PaletteState.self) private var palette

    var body: some View {
        PopoverMenu(header: Bundle.main.appDisplayName, items: items(), selection: $state.selection,
            visibleRows: Theme.Size.pillMenuVisibleRows, onActivate: activate,
            search: .init(placeholder: String(localized: "Search…"), placement: .top))
            .onChange(of: palette.menuQuery) { filtered() }
    }
}
