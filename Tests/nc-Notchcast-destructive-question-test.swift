// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift
// notchcast-reads: Tinycast/Features/Notchcast/NotchcastCore.swift Tinycast/App/AppCore.swift
// notchcast-reads: Tinycast/Windows/Dialog/DialogController.swift

import Foundation

@main @MainActor
enum DestructiveQuestionTests {
    static func main() async throws {
        let defaults = UserDefaults(suiteName: "nc-Notchcast-destructive-question-test.\(UUID())")!
        let context = NotchcastContext(
            defaults: defaults, preferences: NotchcastPreferences(defaults: defaults, switches: []),
            presenter: Presenter(), hub: NotchcastTapHub(syntheticTag: 0, isTrusted: { false }, makeSession: { _ in
                preconditionFailure("a question does not install a tap")
            }),
            transcription: NotchcastTranscriptionRunner(dictation: FakeDictation()),
            now: { Date(timeIntervalSince1970: 0) }, onTapsChanged: {})
        let noPresenter = await context.confirmDestructive("Empty Trash?", nil, "Empty Trash")
        precondition(!noPresenter, "without a presenter there is no consent")
        var cancelLabels: [String] = []
        context.presentDestructiveQuestion = { title, message, confirm, cancel in
            precondition(title == "Empty Trash?" && message == nil && confirm == "Empty Trash")
            cancelLabels.append(cancel)
            return cancel == "Not Now"
        }
        let confirmed = await context.confirmDestructive("Empty Trash?", nil, "Empty Trash", cancelTitle: "Not Now")
        let cancelled = await context.confirmDestructive("Empty Trash?", nil, "Empty Trash")
        precondition(confirmed && !cancelled)
        precondition(cancelLabels == ["Not Now", String(localized: "Cancel")])

        for (path, forwarding) in [
            ("Features/Notchcast/NotchcastCore.swift", "dismissTitle: cancelTitle"),
            ("App/AppCore.swift", "confirmRole: confirmRole, dismissTitle: dismissTitle"),
            ("Windows/Dialog/DialogController.swift", "DialogAction(title: dismissTitle, role: .cancel)")
        ] {
            let source = try String(contentsOfFile: "Tinycast/" + path, encoding: .utf8)
            precondition(source.contains(forwarding), "the live dialog forwards the cancel label")
        }
        print("PASS destructive question cancel label")
    }
}

private final class Presenter: IslandPresenting {
    func showLevel(_ level: IslandLevel) {}
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) {}
    func end(notice id: String) {}
    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {}
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
}
