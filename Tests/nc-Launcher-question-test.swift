// notchcast-linux-ok
// notchcast-sources: Tinycast/Features/Launcher/Model/LauncherQuestionPolicy.swift

@main
enum LauncherQuestionTests {
    static func main() {
        precondition(!LauncherQuestionPolicy.shouldOpenAtLaunch(launchedByUser: true, questionPending: true))
        precondition(LauncherQuestionPolicy.shouldOpenAtLaunch(launchedByUser: true, questionPending: false))
        precondition(LauncherQuestionPolicy.shouldHideForQuestion(isSecret: true, paletteVisible: true))
        precondition(!LauncherQuestionPolicy.shouldHideForQuestion(isSecret: true, paletteVisible: false))
        precondition(!LauncherQuestionPolicy.shouldHideForQuestion(isSecret: false, paletteVisible: true))
        precondition(!LauncherQuestionPolicy.shouldOpenAtLaunch(launchedByUser: false, questionPending: false))
        print("Launcher question tests passed")
    }
}
