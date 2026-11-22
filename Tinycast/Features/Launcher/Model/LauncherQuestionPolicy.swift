nonisolated enum LauncherQuestionPolicy {
    static func shouldOpenAtLaunch(launchedByUser: Bool, questionPending: Bool) -> Bool {
        launchedByUser && !questionPending
    }

    static func shouldHideForQuestion(isPriorityQuestion: Bool, paletteVisible: Bool) -> Bool {
        isPriorityQuestion && paletteVisible
    }
}
