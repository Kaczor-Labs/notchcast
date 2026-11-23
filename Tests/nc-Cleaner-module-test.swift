// notchcast-sources: Tinycast/Features/Notchcast/Cleaner/CleanerModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Cleaner/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Cleaner/Service/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Features/Uninstall/Model/*.swift
// notchcast-sources: Tinycast/Platform/Permissions.swift
// notchcast-sources: Tinycast/Platform/CalendarAccess.swift Tinycast/Platform/CameraAccess.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tests/nc-Cleaner-fixture.swift Tests/NotchcastDictationFixture.swift

import Foundation

@MainActor
private final class CleanerPresenter: IslandPresenting {
    var posts: [IslandNotice] = []
    var moveAccepted = false
    var emptyAccepted = false
    var offers = 0
    var empties = 0

    func showLevel(_ level: IslandLevel) {}
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) { posts.append(notice) }
    func end(notice id: String) {}
    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {}
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
}

@main
@MainActor
struct CleanerModuleTest {
    static func main() async {
        let suite = "app.notchcast.cleaner-test." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let presenter = CleanerPresenter()
        let hub = NotchcastTapHub(syntheticTag: 0, isTrusted: { false }) { _ in
            preconditionFailure("Cleaner does not subscribe to events")
        }
        let context = NotchcastContext(
            defaults: defaults, preferences: NotchcastPreferences(defaults: defaults, switches: []),
            presenter: presenter, hub: hub, transcription: NotchcastTranscriptionRunner(dictation: FakeDictation()),
            now: { .now }, onTapsChanged: {})
        context.confirm = { _, _, _ in presenter.moveAccepted }
        context.presentDestructiveQuestion = { _, _, _, cancelTitle in
            precondition(presenter.posts.last?.progress?.fraction == 1)
            precondition(cancelTitle == "Not Now")
            presenter.offers += 1
            return presenter.emptyAccepted
        }
        let fs = CleanerTestFileSystem()
        let item = CleanerTestFileSystem.item("org.example.cache")
        fs.put(item, size: 64)
        var hasAccess = false
        let session = CleanerSession(
            home: CleanerTestFileSystem.area.home, runner: CleanerRunner(scanner: fs.scanner, runningApps: { .init() }),
            hasAccess: { hasAccess })
        let module = CleanerModule(context: context, session: session, emptyTrash: { presenter.empties += 1 })
        defer { module.stop() }

        await module.scan()?.value
        precondition(session.phase == .needsAccess && session.items.isEmpty)
        precondition(module.clean() == nil && fs.trashCalls.isEmpty)
        hasAccess = true

        await module.scan()?.value
        await module.clean()?.value
        precondition(fs.trashCalls.isEmpty && presenter.posts.isEmpty && presenter.offers == 0)

        presenter.moveAccepted = true
        await module.clean()?.value
        precondition(fs.trashCalls == [item])
        precondition(presenter.posts.compactMap { $0.progress?.fraction } == [0, 1])
        precondition(presenter.offers == 1 && presenter.empties == 0)
        precondition(presenter.posts.last?.symbol == "checkmark" && presenter.posts.last?.progress == nil)

        fs.put(item, size: 64)
        fs.failTrash(of: item)
        await module.scan()?.value
        await module.clean()?.value
        precondition(presenter.offers == 1 && presenter.posts.last?.isFailure == true)

        let another = CleanerTestFileSystem.item("org.example.another")
        fs.remove(item)
        fs.put(another, size: 64)
        presenter.emptyAccepted = true
        await module.scan()?.value
        await module.clean()?.value
        precondition(presenter.offers == 2 && presenter.empties == 1)

        fs.put(another, size: 64)
        defaults.set(false, forKey: CleanerModule.offersEmptyTrash)
        await module.scan()?.value
        await module.clean()?.value
        precondition(presenter.offers == 2 && presenter.empties == 1)
    }
}
