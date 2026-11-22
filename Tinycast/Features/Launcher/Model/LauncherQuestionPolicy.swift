nonisolated enum LauncherQuestionPolicy {
    static func shouldOpenAtLaunch(launchedByUser: Bool, questionPending: Bool) -> Bool {
        launchedByUser && !questionPending
    }

    static func shouldHideForQuestion(isSecret: Bool, paletteVisible: Bool) -> Bool {
        isSecret && paletteVisible
    }
}
