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
    var emptyFails = false

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
        var moveQuestions = 0
        context.confirm = { _, _, _ in
            moveQuestions += 1
            return presenter.moveAccepted
        }
        let askToEmpty: @MainActor (String, String, String, String) async -> Bool = { _, _, _, cancelTitle in
            precondition(presenter.posts.last?.progress?.fraction == 1)
            precondition(cancelTitle == "Not Now")
            presenter.offers += 1
            return presenter.emptyAccepted
        }
        let fs = CleanerTestFileSystem()
        let item = CleanerTestFileSystem.item("org.example.cache")
        fs.put(item, size: 64)
        var hasAccess = false
        var onScanStart: (@MainActor () -> Void)?
        let runner = CleanerRunner(scanner: fs.scanner, runningApps: {
            onScanStart?()
            return .init()
        })
        let session = CleanerSession(
            home: CleanerTestFileSystem.area.home, runner: runner,
            hasAccess: { hasAccess })
        let module = CleanerModule(
            context: context, session: session, askToEmptyTrash: askToEmpty,
            emptyTrash: {
                presenter.empties += 1
                if presenter.emptyFails { throw CocoaError(.fileWriteNoPermission) }
                return "Trash Is Already Empty"
            })
        defer { module.stop() }
        let review = module.beginReview()

        func activateVisibleItems() -> Task<Void, Never>? {
            module.activateReview(visibleItems: session.items) { preconditionFailure("all items are visible") }
        }

        await module.scan(for: review)?.value
        precondition(session.phase == .needsAccess && session.items.isEmpty)
        precondition(activateVisibleItems() == nil && fs.trashCalls.isEmpty)
        hasAccess = true

        await module.scan(for: review)?.value
        let noMatches = session.items(matching: "no matching cache")
        precondition(noMatches.isEmpty && session.selection?.checked.count == 1
                     && session.hiddenSelectionCount(among: noMatches) == 1,
                     "zero search matches still count the hidden checked cache")
        var revealed = false
        let hiddenMove = module.activateReview(visibleItems: noMatches) { revealed = true }
        await hiddenMove?.value
        precondition(revealed && hiddenMove == nil && moveQuestions == 0 && session.selection?.checked == [item],
                     "the first activation reveals the selection without opening the move question")
        await activateVisibleItems()?.value
        precondition(fs.trashCalls.isEmpty && presenter.posts.isEmpty && presenter.offers == 0)

        presenter.moveAccepted = true
        await activateVisibleItems()?.value
        precondition(fs.trashCalls == [item])
        precondition(presenter.posts.compactMap { $0.progress?.fraction } == [0, 1])
        precondition(presenter.offers == 1 && presenter.empties == 0)
        precondition(presenter.posts.last?.symbol == "checkmark" && presenter.posts.last?.progress == nil)

        fs.put(item, size: 64)
        fs.failTrash(of: item)
        await module.scan(for: review)?.value
        await activateVisibleItems()?.value
        precondition(presenter.offers == 1 && presenter.posts.last?.isFailure == true)

        let another = CleanerTestFileSystem.item("org.example.another")
        let missing = CleanerTestFileSystem.item("org.example.missing")
        let open = CleanerTestFileSystem.item("org.example.open")
        for url in [another, missing, open] { fs.put(url, size: 64) }
        presenter.emptyAccepted = true
        await module.scan(for: review)?.value
        fs.remove(missing)
        do {
            try fs.holdOpen(open)
        } catch {
            preconditionFailure("could not set up the open file: \(error)")
        }
        await activateVisibleItems()?.value
        precondition(presenter.offers == 2 && presenter.empties == 1)
        precondition(session.report?.entries.count == 4)
        precondition(presenter.posts.last?.isFailure == true
                     && presenter.posts.last?.text ==
                        "1 Moved to Trash · 1 Missing · 1 Skipped · 1 Failed\nTrash Is Already Empty",
                     "a mixed move reports each outcome alongside Finder’s no-op feedback")

        fs.remove(item)
        fs.remove(open)
        fs.put(another, size: 64)
        presenter.emptyFails = true
        await module.scan(for: review)?.value
        await activateVisibleItems()?.value
        precondition(presenter.offers == 3 && presenter.empties == 2)
        let moveSummary = "Moved \(MeasuredSize(bytes: 64).formatted) to the Trash"
        precondition(presenter.posts.last?.isFailure == true
                     && presenter.posts.last?.text == moveSummary + "\nCouldn’t Empty the Trash",
                     "an emptying failure keeps the successful move result")

        let unverified = CleanerTestFileSystem.item("org.example.unverified")
        for url in [another, unverified] { fs.put(url, size: 64) }
        fs.loseInTrash(unverified)
        await module.scan(for: review)?.value
        await activateVisibleItems()?.value
        precondition(session.report?.movedCount == 1 && session.report?.unverifiedCount == 1)
        precondition(presenter.offers == 3 && presenter.empties == 2,
                     "a batch with an unverified move gets no Empty Trash offer")
        precondition(presenter.posts.last?.isFailure == true
                     && presenter.posts.last?.text ==
                        "1 Moved to Trash · 1 Unverified\nCheck the Trash Before Emptying It",
                     "an unverified move tells the user to check the Trash")

        fs.put(another, size: 64)
        defaults.set(false, forKey: CleanerModule.offersEmptyTrash)
        await module.scan(for: review)?.value
        await activateVisibleItems()?.value
        precondition(presenter.offers == 3 && presenter.empties == 2)

        await module.scan(for: review)?.value
        onScanStart = {
            precondition(session.phase == .scanning)
            module.closeReview(review)
        }
        let refreshed = module.scan(for: review)
        await refreshed?.value
        onScanStart = nil
        precondition(refreshed?.isCancelled == true && session.phase == .idle,
                     "closing the review cancels its refresh")
        precondition(module.scan(for: review) == nil, "a closed screen cannot restart its scan")

        let replaced = module.beginReview()
        let oldScan = module.scan(for: replaced)
        let current = module.beginReview()
        let currentScan = module.scan(for: current)
        module.closeReview(replaced)
        await currentScan?.value
        precondition(oldScan?.isCancelled == true && currentScan?.isCancelled == false && session.phase == .review,
                     "closing a replaced screen keeps the new scan")
        onScanStart = { module.closeReview(current) }
        let replacementRefresh = module.scan(for: current)
        await replacementRefresh?.value
        onScanStart = nil
        precondition(replacementRefresh?.isCancelled == true && session.phase == .idle,
                     "closing the replacement cancels its refresh")

        let refused = module.beginReview()
        let refusedScan = module.scan(for: refused)
        module.closeReview(refused)
        await refusedScan?.value
        precondition(refusedScan?.isCancelled == true && session.phase == .idle && session.items.isEmpty,
                     "a refused screen cancels its scan")
    }
}
