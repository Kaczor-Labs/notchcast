// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift

import Foundation

@MainActor
@main
enum LauncherQuestionTests {
    static func main() async {
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
        let launcher = LauncherProbe()
        controller.wireAskSecret { _, _, _, _, _ in
            launcher.presentQuestion(priority: NotchcastQuestion.takesLauncherPriority)
        }

        launcher.start(userLaunched: true, questionPending: controller.hasPendingQuestion)
        precondition(!launcher.visible, "a question pending at launch holds the launcher")
        let startupAnswer = await question.ask()
        precondition(startupAnswer != nil && !launcher.visible, "answering the startup question leaves it closed")

        launcher.start(userLaunched: false, questionPending: controller.hasPendingQuestion)
        precondition(!launcher.visible, "a background launch skips the launcher")
        launcher.start(userLaunched: true, questionPending: controller.hasPendingQuestion)
        precondition(launcher.visible, "a user launch without a pending question opens the launcher")

        _ = await question.ask()
        precondition(launcher.visible, "an unregistered question keeps the launcher open")
        for answer: String? in ["answer", nil] {
            launcher.start(userLaunched: true, questionPending: controller.hasPendingQuestion)
            launcher.answer = answer
            question.hasPendingQuestion = true
            let response = await question.ask()
            precondition(!launcher.visibleAtPresentation, "a later question closes the launcher before presenting")
            precondition(response == answer && !launcher.visible, "answering or cancelling leaves the launcher closed")
        }
        print("PASS launcher questions hold startup, close before presentation, and leave the launcher closed")
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

@MainActor
private final class LauncherProbe {
    var visible = false
    var visibleAtPresentation = false
    var answer: String? = "answer"

    func start(userLaunched: Bool, questionPending: Bool) {
        visible = LauncherQuestionPolicy.shouldOpenAtLaunch(launchedByUser: userLaunched, questionPending: questionPending)
    }

    func presentQuestion(priority: Bool) -> String? {
        if LauncherQuestionPolicy.shouldHideForQuestion(isPriorityQuestion: priority, paletteVisible: visible) {
            visible = false
        }
        visibleAtPresentation = visible
        return answer
    }
}

private final class SilentPresenter: IslandPresenting {
    func showLevel(_ level: IslandLevel) {}
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) {}
    func end(notice id: String) {}
    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {}
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
}
