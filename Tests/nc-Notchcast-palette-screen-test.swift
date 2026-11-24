// notchcast-hosted-only
// notchcast-sources: Tinycast/Palette/PaletteState.swift Tinycast/Palette/PaletteMode.swift
// notchcast-sources: Tinycast/Palette/HoverArming.swift Tinycast/Palette/PaletteCoordinator.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastSurfaces.swift
// notchcast-sources: Tinycast/Features/Notchcast/NotchcastSurfaces+Live.swift

import AppKit

@main @MainActor
enum AddOnPaletteTests {
    static func main() {
        let core = AppCore()
        let palette = core.palette
        let coordinator = core.paletteCoordinator
        let surfaces = NotchcastSurfaces(core: core)
        var closed = 0
        func open() {
            surfaces.openPalette(title: "Review Items", prompt: "Filter items…", makeScreen: Screen.init) {
                precondition(palette.customScreen == nil, "the screen is cleared before cancellation")
                closed += 1
            }
        }

        coordinator.showPalette(mode: .launcher, seeding: "sample")
        palette.selection = 2
        open()
        precondition(palette.isVisible && palette.mode == .customScreen, "the existing palette hosts the screen")
        precondition(palette.customScreen?.title == "Review Items" && palette.customScreen?.prompt == "Filter items…")
        precondition(palette.query.isEmpty && palette.selection == 0, "the new screen starts fresh")
        palette.query = "example"
        let screen = palette.customScreen?.makeScreen(palette.query) as? Screen
        precondition(screen?.query == "example", "the screen receives the live search text")
        screen?.selectRow(1)
        precondition(palette.selection == 1, "a row click updates the host's selection")
        palette.query = ""
        screen?.selectRow(2)
        precondition(palette.selection == 1, "a row from an earlier query cannot move selection")
        precondition(palette.pop(preservingSelection: true), "back returns to the launcher")
        screen?.selectRow(0)
        precondition(palette.query == "sample" && palette.selection == 2)
        precondition(closed == 1 && palette.customScreen == nil)

        open()
        let original = palette.customScreen?.makeScreen(palette.query) as? Screen
        open()
        precondition(closed == 2 && palette.customScreen != nil, "replacing a screen closes the previous one")
        original?.selectRow(1)
        precondition(palette.selection == 0, "a replaced screen cannot move the current selection")
        let replacement = palette.customScreen?.makeScreen(palette.query) as? Screen
        replacement?.selectRow(2)
        precondition(palette.selection == 2, "the replacement can still move selection")
        coordinator.hidePalette()
        coordinator.hidePalette()
        replacement?.selectRow(2)
        precondition(palette.selection == 0, "a closed screen cannot move selection")
        precondition(closed == 3 && palette.customScreen == nil, "close releases the screen exactly once")
        precondition(!palette.isVisible && palette.mode == .launcher && !palette.canGoBack)
        coordinator.togglePalette()
        precondition(coordinator.isShowing(.launcher), "the launcher cannot restore a closed screen")

        open()
        coordinator.showPalette(mode: .fileSearch)
        precondition(closed == 4 && palette.customScreen == nil, "leaving the screen cancels its work")
        precondition(palette.backStack.allSatisfy { $0.mode != .customScreen }, "back cannot resurrect it")

        coordinator.dialogPresentationChanged(true)
        open()
        precondition(closed == 5 && palette.customScreen == nil && !palette.isVisible, "a refused open closes at once")
        print("PASS add-on palette lifecycle and selection")
    }
}

@MainActor
protocol PaletteScreen {}

private struct Screen: PaletteScreen {
    let query: String
    let selectRow: (Int) -> Void
}

@MainActor
final class AppCore {
    let palette = PaletteState()
    let settings = AppSettings()
    let island = Island()
    lazy var paletteCoordinator = PaletteCoordinator(
        palette: palette, settings: settings, appIndex: AppIndex(), fileSearch: FileSearchSession(),
        menuSearch: MenuSearchSession(), windowSwitch: WindowSwitchSession(),
        windowController: PaletteWindowController(palette: palette))
}

@MainActor
final class PaletteWindowController {
    let palette: PaletteState
    var isVisible: Bool { palette.isVisible }
    var visibleFrame: CGRect? { nil }
    var anchorView: NSView? { nil }
    var previousApp: NSRunningApplication? { nil }
    var previousOwnWindow: NSWindow? { nil }
    var isPoppedToRoot: Bool { false }

    init(palette: PaletteState) { self.palette = palette }
    func show() { palette.noteVisible(true) }
    func hide(restoreFocus: Bool) { palette.noteVisible(false) }
    func consumePreservedState() -> Bool { false }
    func popToRootNow() { palette.prepare(mode: .launcher) }
    func applyCollapsed(_ collapsed: Bool) {}
    func beginDrag() {}
    func endDrag() {}
}

@MainActor struct NotchcastServices { let surfaces = NotchcastSurfaces() }
@MainActor struct NotchcastContext { let services = NotchcastServices() }
enum NotchcastQuestion { static let takesLauncherPriority = true }
enum ClipboardFilter { case all }
enum FileSearchFilter { case all }
enum EmojiCategoryFilter { case all }
struct EmojiGridColumns {}
struct EmojiGridZoom {}
enum CustomCommand { static let sfSymbol = "command" }
enum Quicklink { static let sfSymbol = "link" }
enum FrontmostApp { static var current: NSRunningApplication? { nil } }
struct AppEntry { let id: String; let name: String }
struct AppSettings {
    let compactMode = false
    let islandOutlineWhenOpen = true
    let interfaceSize = InterfaceSize()
}
struct InterfaceSize { let metrics = Metrics() }
struct Metrics { let scale = 1.0 }
struct Island { func frosted(on display: UInt32?) -> Bool { false } }
struct AppIndex { func refresh() async {} }
struct FileSearchSession { func search(_ query: String) {} }
struct MenuSearchSession {
    func filter(_ query: String) {}
    func reset() {}
}
struct WindowSwitchSession {
    func filter(_ query: String) {}
    func reset() {}
}
