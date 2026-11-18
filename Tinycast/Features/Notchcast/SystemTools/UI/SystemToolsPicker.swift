import AppKit
import SwiftUI

/// The stock menu in its panel over one picker model: typing filters, ↩ or ⌥↩ chooses.
@MainActor
final class SystemToolsPicker {
    /// Optical centring, as Notchcast's own questions sit: an exactly centred panel reads low.
    private static let centerLift: CGFloat = 0.08

    private let session: any SystemToolsPicking
    private let panel = MenuPanel()
    private let palette = PaletteState()
    private let hosting: NSHostingView<AnyView>
    private var refreshTask: Task<Void, Never>?

    private init(session: any SystemToolsPicking, surfaces: NotchcastSurfaces) {
        self.session = session
        let metrics = InterfaceMetrics(scale: CGFloat(surfaces.interfaceScale()))
        let frosted = surfaces.isFrosted()
        hosting = NSHostingView(rootView: AnyView(EmptyView()))
        hosting.rootView = AnyView(
            SystemToolsMenu(
                session: session, activate: { [weak self] in self?.activate($0) },
                resized: { [weak self] in Task { @MainActor in self?.place() } }
            )
            .environment(palette).environment(\.metrics, metrics).environment(\.islandFrosted, frosted))
        hosting.sizingOptions = [.intrinsicContentSize]
        panel.hasShadow = frosted
        panel.contentView = hosting
        panel.setAccessibilityLabel(session.title)
    }

    static func present(_ session: any SystemToolsPicking, surfaces: NotchcastSurfaces) -> @MainActor () -> Void {
        let picker = SystemToolsPicker(session: session, surfaces: surfaces)
        picker.open()
        return { picker.close() }
    }

    private func open() {
        panel.onKeyDown = { [weak self] in self?.handleKey($0) ?? false }
        panel.onResignKey = { [weak self] _ in self?.close() }
        place()
        panel.makeKeyAndOrderFront(nil)
        guard let interval = session.refreshInterval else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled, let session = self?.session {
                await session.refresh()
                try? await Task.sleep(for: interval)
            }
        }
    }

    private func close() {
        refreshTask?.cancel()
        refreshTask = nil
        panel.onKeyDown = nil
        panel.onResignKey = nil
        panel.orderOut(nil)
    }

    /// Centred on the pointer's display once, then grown or shrunk from a fixed top edge.
    private func place() {
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        guard size.width > 0, size.height > 0, let visible = (NSScreen.underCursor ?? NSScreen.main)?.visibleFrame
        else { return }
        let shown = panel.isVisible ? panel.frame : nil
        let top = shown?.maxY ?? visible.midY + visible.height * Self.centerLift + size.height / 2
        let midX = shown?.midX ?? visible.midX
        panel.setFrame(
            NSRect(x: midX - size.width / 2, y: top - size.height, width: size.width, height: size.height).integral,
            display: true)
    }

    private func activate(_ index: Int) {
        guard session.pickerRows.indices.contains(index) else { return }
        let option = NSEvent.modifierFlags.contains(.option)
        close()
        session.activate(index, option: option)
    }

    private func move(_ step: Int) {
        let count = session.pickerRows.count
        guard count > 0 else { return }
        session.selectedIndex = (session.selectedIndex + step + count) % count
    }

    /// The pill menu's keys: Esc clears the query, then closes.
    private func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.charactersIgnoringModifiers == "\u{1B}" {
            if palette.menuQuery.isEmpty { close() } else { palette.menuQuery = "" }
            return true
        }
        switch event.specialKey {
        case .some(.downArrow) where modifiers.isEmpty: move(1)
        case .some(.upArrow) where modifiers.isEmpty: move(-1)
        case .some(.carriageReturn), .some(.enter): activate(session.selectedIndex)
        default:
            switch (modifiers, event.charactersIgnoringModifiers?.lowercased()) {
            case ([.control], "n"): move(1)
            case ([.control], "p"): move(-1)
            default: return false
            }
        }
        return true
    }
}

private struct SystemToolsMenu: View {
    let session: any SystemToolsPicking
    let activate: (Int) -> Void
    let resized: () -> Void
    @Environment(PaletteState.self) private var palette

    var body: some View {
        PopoverMenu(
            header: session.header,
            items: session.pickerRows.map(item),
            selection: Binding(get: { session.selectedIndex }, set: { session.selectedIndex = $0 }),
            onActivate: activate,
            search: .init(placeholder: session.placeholder, placement: .top))
            .onChange(of: palette.menuQuery) { session.query = palette.menuQuery }
            .onChange(of: session.pickerRows.count) { resized() }
    }

    private func item(_ row: SystemToolsPickerRow) -> PopoverMenuItem {
        PopoverMenuItem(
            title: row.title, icon: row.bundlePath.map { .file(path: $0) } ?? .symbol(row.symbol), detail: row.detail) {}
    }
}
