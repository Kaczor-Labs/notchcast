// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift Tinycast/Palette/PaletteCoordinator.swift
// notchcast-reads: Tinycast/App/AppCore.swift

import AppKit

@MainActor
@main
enum LauncherQuestionTests {
    static func main() async throws {
        let suite = "nc-Launcher-question-test.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = NotchcastController(
            addons: [QuestionAddon.self], defaults: defaults,
            hub: NotchcastTapHub(syntheticTag: 0, isTrusted: { true }, makeSession: { _ in
                fatalError("the question add-on declares no tap")
            }),
            dictation: FakeDictation(), presenter: SilentPresenter())
        controller.start()
        defer { controller.stop() }
        let question = controller.context(forSwitch: "question")!.module(QuestionModule.self)!
        let window = PaletteWindowController()
        let launcher = PaletteCoordinator(
            palette: PaletteState(), settings: AppSettings(), appIndex: AppIndex(),
            fileSearch: FileSearchSession(), menuSearch: MenuSearchSession(), windowSwitch: WindowSwitchSession(),
            windowController: window)
        var answer: String? = "answer"
        var visibleAtPresentation = false
        controller.wireAskSecret { _, _, _, _, _ in
            launcher.dialogPresentationChanged(true)
            defer { launcher.dialogPresentationChanged(false) }
            visibleAtPresentation = window.isVisible
            if NotchcastQuestion.takesLauncherPriority {
                NotchcastQuestion.$takesLauncherPriority.withValue(false) {
                    let shows = window.showCount
                    launcher.togglePalette()
                    precondition(window.showCount == shows, "the launcher hotkey is refused during a priority question")
                    launcher.showPalette(mode: .launcher, restoreAnyMode: true)
                    precondition(window.showCount == shows, "Dock reopen is refused during a priority question")
                    launcher.showPalette(mode: .launcher)
                    precondition(window.showCount == shows, "menu-bar Open is refused during a priority question")
                }
            }
            return answer
        }

        launcher.showLauncherAtLaunch(launchedByUser: true, questionPending: controller.hasPendingQuestion)
        precondition(!window.isVisible, "a question pending at launch holds the launcher")
        let startupAnswer = await question.ask()
        precondition(startupAnswer != nil && !window.isVisible, "answering the startup question leaves it closed")

        launcher.showLauncherAtLaunch(launchedByUser: false, questionPending: controller.hasPendingQuestion)
        precondition(!window.isVisible, "a background launch skips the launcher")
        launcher.showLauncherAtLaunch(launchedByUser: true, questionPending: controller.hasPendingQuestion)
        precondition(window.isVisible, "a user launch without a pending question opens the launcher")

        _ = await question.ask()
        precondition(window.isVisible, "an unregistered question keeps the launcher open")
        for reply: String? in ["answer", nil] {
            answer = reply
            question.hasPendingQuestion = true
            let response = await question.ask()
            precondition(!visibleAtPresentation, "a later question closes the launcher before presenting")
            precondition(response == reply && !window.isVisible, "answering or cancelling leaves the launcher closed")
            launcher.togglePalette()
            precondition(window.isVisible, "the launcher can reopen after a priority question ends")
        }

        let core = try String(contentsOfFile: "Tinycast/App/AppCore.swift", encoding: .utf8)
        precondition(core.contains("paletteCoordinator.dialogPresentationChanged(isPresenting)"),
                     "AppCore forwards the real dialog presentation callback")
        precondition(core.contains("paletteCoordinator.showLauncherAtLaunch("),
                     "AppCore uses the launch decision after add-ons start")
        print("PASS priority questions hold startup, close and block the launcher, and allow reopening after dismissal")
    }
}

private enum QuestionAddon: NotchcastAddon {
    static let switches = [
        NotchcastSwitch(id: "question", title: "Question", subtitle: "", category: .filesDownloads, defaultEnabled: true)
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        QuestionModule(context: context)
    }
}

@MainActor
private final class QuestionModule: NotchcastModule {
    let context: NotchcastContext
    var hasPendingQuestion = true

    init(context: NotchcastContext) { self.context = context }

    func start() {}
    func stop() {}

    func ask() async -> String? {
        defer { hasPendingQuestion = false }
        return await NotchcastQuestion.$takesLauncherPriority.withValue(hasPendingQuestion) {
            await context.askSecret?("Question", nil, "Answer", "Continue")
        }
    }
}

private final class SilentPresenter: IslandPresenting {
    func showLevel(_ level: IslandLevel) {}
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) {}
    func end(notice id: String) {}
    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {}
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
}

@MainActor
final class PaletteWindowController {
    private(set) var isVisible = false
    private(set) var showCount = 0
    var visibleFrame: CGRect? { nil }
    var anchorView: NSView? { nil }
    var previousApp: NSRunningApplication? { nil }
    var previousOwnWindow: NSWindow? { nil }
    var isPoppedToRoot: Bool { false }

    func show() {
        showCount += 1
        isVisible = true
    }

    func hide(restoreFocus: Bool) { isVisible = false }
    func consumePreservedState() -> Bool { false }
    func popToRootNow() {}
    func applyCollapsed(_ collapsed: Bool) {}
    func beginDrag() {}
    func endDrag() {}
}

@MainActor
final class PaletteState {
    var mode = PaletteMode.launcher
    var query = ""
    var forceExpanded = false
    var argumentEntryID: String?
    var commandArguments: [String: String] = [:]
    var pendingArgumentEntryID: String?

    func prepare(mode: PaletteMode) { self.mode = mode }
    func push(mode: PaletteMode) { self.mode = mode }
    static func argumentKey(_ id: String, _ field: String) -> String { id + field }
}

enum PaletteMode { case launcher, fileSearch, menuSearch, switchWindows }
struct AppEntry {
    let id: String
    let name: String
}
struct AppSettings { let compactMode = false }
enum FrontmostApp { static var current: NSRunningApplication? { nil } }

@MainActor
final class AppIndex { func refresh() async {} }
struct FileSearchSession { func search(_ query: String) {} }
struct MenuSearchSession {
    func filter(_ query: String) {}
    func reset() {}
}
struct WindowSwitchSession {
    func filter(_ query: String) {}
    func reset() {}
}
