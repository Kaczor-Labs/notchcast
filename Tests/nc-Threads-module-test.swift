// notchcast-sources: Tinycast/Features/Notchcast/Threads/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Threads/Service/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tests/NotchcastTapFixtures.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift
// notchcast-sources: Tests/nc-Threads-fixtures.swift
import Foundation

func check(_ condition: Bool, _ message: @autoclosure () -> String) {
    guard condition else { fatalError("nc-Threads-module-test: \(message())") }
}

@MainActor
final class ThreadsRecorder: IslandPresenting {
    var notices: [IslandNotice] = []
    var taps: [String: @MainActor () -> Void] = [:]
    var page: IslandPage?
    var pageCalls = 0
    var action: (@MainActor (String) -> Void)?
    var status: IslandStatus?
    var statusTap: (@MainActor () -> Void)?
    var watcher: (@MainActor (Bool) -> Void)?
    var shown: [String] = []

    func showLevel(_ level: IslandLevel) { check(false, "Threads shows no level") }
    func end(notice id: String) {}
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}

    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) {
        notices.append(notice)
        taps[notice.id] = onTap
    }

    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {
        check(id == ThreadsPage.id, "one status, its own")
        self.status = status
        statusTap = onTap
    }

    func setPage(_ page: IslandPage?, id: String, onAction: (@MainActor (String) -> Void)?) {
        check(id == ThreadsPage.id, "one page, its own")
        self.page = page
        pageCalls += 1
        action = onAction
    }

    func watchPages(id: String, onChange: (@MainActor (Bool) -> Void)?) { watcher = onChange }
    func showPage(id: String) { shown.append(id) }

    var rows: [IslandPageRow] { (page?.blocks ?? []).compactMap { if case .row(let row) = $0 { row } else { nil } } }
}

/// The module as its hook starts it, on a scratch suite and a scratch file, with the clock fixed.
@MainActor
@main
struct ThreadsModuleTests {
    static func main() async {
        decoding()
        pages()
        notices()
        links()
        await unset()
        await announcesOnceAcrossRestart()
        await oldAndMissing()
        await opens()
        await fileEvent()
        print("PASSED")
    }

    final class Rig {
        let suite = "nc-threads-test.\(UUID().uuidString)"
        let defaults: UserDefaults
        let folder: URL
        var file: URL { folder.appending(path: "waits.json") }
        var opened: [URL] = []

        init() {
            defaults = UserDefaults(suiteName: suite) ?? .standard
            defaults.removePersistentDomain(forName: suite)
            folder = FileManager.default.temporaryDirectory.appending(path: "nc-threads-\(UUID().uuidString)")
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            } catch {
                preconditionFailure("scratch: \(error)")
            }
        }

        func write(_ data: Data) {
            do {
                try data.write(to: file, options: .atomic)
            } catch {
                preconditionFailure("write: \(error)")
            }
        }

        /// A fresh module and context on the same suite: what a restart of the app sees.
        @MainActor
        func start(_ presenter: ThreadsRecorder, path: Bool = true) -> (ThreadsModule, NotchcastContext) {
            if path { defaults.set(file.path, forKey: ThreadsPreferences.fileKey) }
            let hub = NotchcastTapHub(syntheticTag: 0, isTrusted: { false }) { _ in
                preconditionFailure("the harness never installs a tap")
            }
            let context = NotchcastContext(
                defaults: defaults, preferences: NotchcastPreferences(defaults: defaults, switches: []),
                presenter: presenter, hub: hub, transcription: NotchcastTranscriptionRunner(dictation: FakeDictation()),
                now: { ThreadsFixtures.now }, onTapsChanged: {})
            let module = ThreadsModule(context: context) { [unowned self] in opened.append($0) }
            context.attach(module)
            module.start()
            return (module, context)
        }
    }

    static func decoding() {
        let document = ThreadsFixtures.document(rows: [ThreadsFixtures.question, ThreadsFixtures.door,
                                                       ThreadsFixtures.later])
        check(document.waits.map(\.kind) == [.question, .doorAsk, .doorAsk], "\(document.waits.map(\.kind))")
        check(document.waits[1].threadID == "thread-door" && document.waits[1].title == nil,
              "a door ask opens the door's thread")
        check(document.waits[0].question == "Keep the old tax field or switch to the new one?", "the first question")
        check(document.waits[2].later, "later is read")
        check(document.sources.count == 3 && document.sources[2].ageSeconds == 70, "\(document.sources)")
        check((try? ThreadsDocument.decode(ThreadsFixtures.json(version: 2, rows: []))) == nil,
              "another major version is not read as v1")
        check((try? ThreadsDocument.decode(Data("{".utf8))) == nil, "a broken file is not a document")
        var old = ThreadsFixtures.question
        old.id = nil
        let board = ThreadsFixtures.board(rows: [old])
        check(board.waiting.count == 1 && board.announceable.isEmpty,
              "a document older than ids lists its waits and announces none")
    }

    static func pages() {
        let boards = Dictionary(uniqueKeysWithValues: ThreadsFixtures.pages.map { ($0.name, $0.board) })
        func titles(_ name: String) -> [String] {
            (ThreadsPage.page(boards[name]!)?.blocks ?? []).compactMap { if case .row(let row) = $0 { row.title } else { nil } }
        }
        check(titles("list") == ["Billing page redesign", "Door", "Nightly backup check", "Release 2.4 notes",
                                 "Not waiting on you", "Door"], "two groups, newest first: \(titles("list"))")
        let list = ThreadsPage.page(boards["list"]!)
        check(list?.badge == 4 && list?.line.text == "4 threads wait on you" && list?.title == "Threads", "\(list!)")
        let rows = (list?.blocks ?? []).compactMap { if case .row(let row) = $0 { row } else { nil } }
        check(rows[0].trailing == "NEO · 2 min" && rows[2].detail == "Failed" && rows[5].detail?.hasPrefix("Later: ") == true,
              "machine and age, the failed word, the later mark: \(rows)")
        check(rows[4].id == nil && rows[4].symbol == nil, "the group header is a plain row")
        check(titles("nothing-waits") == ["Nothing waits on you", "Not waiting on you", "Door"], "\(titles("nothing-waits"))")
        check(ThreadsPage.page(ThreadsFixtures.board(rows: [])) == nil, "nothing at all: no page")
        check(titles("old-document").first == "t3chad is not reporting" && titles("old-document").count == 4,
              "an old document keeps its rows under the line: \(titles("old-document"))")
        check(ThreadsPage.page(boards["old-document"]!)?.line.text == "t3chad is not reporting", "the Home line says so")
        check(titles("no-document") == ["t3chad is not reporting"], "\(titles("no-document"))")
        check(titles("machine-silent").first == "BOX last heard 9 min ago", "\(titles("machine-silent"))")
        check(ThreadsPage.page(boards["one"]!)?.line.text == "Billing page redesign asks you", "one waits")
        check(ThreadsPage.page(ThreadsBoard(configured: false, document: nil, now: ThreadsFixtures.now)) == nil,
              "no file set: no page")
        let status = ThreadsPage.status(boards["list"]!)
        check(status?.text == "4" && status?.tone == .critical && status?.label == "4 threads wait on you, 1 failed",
              "the count is red while a run failed: \(String(describing: status))")
        check(ThreadsPage.status(boards["one"]!)?.tone == nil, "and plain otherwise")
        check(ThreadsPage.status(boards["nothing-waits"]!) == nil, "no count while nothing waits")
    }

    static func notices() {
        let wait = { (row: ThreadsFixtures.Row) in ThreadsFixtures.document(rows: [row]).waits[0] }
        check(ThreadsPage.notice(wait(ThreadsFixtures.question)).text
              == "Billing page redesign asks: Keep the old tax field or switch to the new one?", "the thread and its ask")
        check(ThreadsPage.notice(wait(ThreadsFixtures.door)).text == "Door asks: Move the weekly report to Mondays?", "door")
        let failed = ThreadsPage.notice(wait(ThreadsFixtures.failed))
        check(failed.isFailure && failed.text == "Nightly backup check failed", "a failed run is a failure notice")
        check(ThreadsPage.notice(wait(ThreadsFixtures.approval)).text == "Release 2.4 notes wants your approval", "approval")
        let together = ThreadsPage.notices([wait(ThreadsFixtures.question), wait(ThreadsFixtures.failed),
                                            wait(ThreadsFixtures.door)])
        check(together.map(\.notice.text) == ["2 threads wait on you: Billing page redesign, Door",
                                              "Nightly backup check failed"],
              "two together are one notice, a failed run its own: \(together.map(\.notice.text))")
        check(together[0].wait == nil && together[1].wait?.kind == .failedRun, "the batch opens the page")
    }

    static func links() {
        let wait = ThreadsFixtures.document(rows: [ThreadsFixtures.question]).waits[0]
        check(ThreadsLink.url(wait)?.absoluteString == "t3code://threads/env-one/thread-billing", "T3's thread link")
        for bad in ["", "../x", "a/b", "a b", "a?b", ".hidden", "é"] {
            var unsafe = wait
            unsafe.threadID = bad
            check(ThreadsLink.url(unsafe) == nil, "\(bad) never reaches a URL")
        }
        check(!ThreadsLink.isOpenable(URL(string: "https://example.com")!), "only T3's scheme opens")
        var shown = ThreadsShown()
        let waits = ThreadsFixtures.document(rows: [ThreadsFixtures.question, ThreadsFixtures.door]).waits
        check(shown.take(waits).count == 2 && shown.take(waits).isEmpty, "a wait is taken once")
        var full = ThreadsShown(ids: (0..<ThreadsShown.cap).map { "old-\($0)" })
        _ = full.take(waits)
        check(full.ids.count == ThreadsShown.cap && full.ids.last == "wait-door-report", "the oldest ids go first")
    }

    static func unset() async {
        let rig = Rig()
        let presenter = ThreadsRecorder()
        let (module, _) = rig.start(presenter, path: false)
        await module.reload().value
        check(presenter.page == nil && presenter.status == nil && presenter.notices.isEmpty,
              "with no file set the island shows nothing")
        module.stop()
    }

    static func announcesOnceAcrossRestart() async {
        let rig = Rig()
        rig.write(ThreadsFixtures.json(rows: [ThreadsFixtures.question, ThreadsFixtures.door, ThreadsFixtures.failed,
                                              ThreadsFixtures.later]))
        let presenter = ThreadsRecorder()
        var (module, context) = rig.start(presenter)
        await module.reload().value
        check(presenter.notices.map(\.text) == ["2 threads wait on you: Billing page redesign, Door",
                                                "Nightly backup check failed"],
              "a later ask is never announced: \(presenter.notices.map(\.text))")
        check(presenter.status?.text == "3" && presenter.page?.badge == 3, "the count and the page")
        check(context.commands.map(\.name) == ["Billing page redesign", "Door", "Nightly backup check"],
              "one launcher command per waiting thread: \(context.commands.map(\.name))")
        await module.reload().value
        check(presenter.notices.count == 2, "a reread announces nothing again")

        module.stop()
        context.detach()
        let again = ThreadsRecorder()
        (module, context) = rig.start(again)
        await module.reload().value
        check(again.notices.isEmpty, "after a restart no wait already shown is announced: \(again.notices.map(\.text))")
        check(again.status?.text == "3", "while the count comes back")

        rig.write(ThreadsFixtures.json(rows: [ThreadsFixtures.question, ThreadsFixtures.door, ThreadsFixtures.failed,
                                              ThreadsFixtures.approval]))
        await module.reload().value
        check(again.notices.map(\.text) == ["Release 2.4 notes wants your approval"], "only the new one")
        module.stop()
        check(again.page == nil && again.status == nil, "stop clears the page and the count")
    }

    static func oldAndMissing() async {
        let rig = Rig()
        rig.write(ThreadsFixtures.json(age: 20 * 60, rows: [ThreadsFixtures.question]))
        let presenter = ThreadsRecorder()
        let (module, _) = rig.start(presenter)
        await module.reload().value
        check(presenter.notices.isEmpty, "an old document announces nothing")
        check(presenter.rows.map(\.title) == ["t3chad is not reporting", "Billing page redesign"], "\(presenter.rows)")
        rig.write(ThreadsFixtures.json(rows: [ThreadsFixtures.question]))
        await module.reload().value
        check(presenter.notices.count == 1, "fresh again, its wait is announced")
        do {
            try FileManager.default.removeItem(at: rig.file)
        } catch {
            preconditionFailure("remove: \(error)")
        }
        await module.reload().value
        check(presenter.rows.map(\.title) == ["Billing page redesign"], "a vanished file keeps the last list")
        rig.write(Data("{ not json".utf8))
        await module.reload().value
        check(presenter.rows.map(\.title) == ["Billing page redesign"] && presenter.notices.count == 1,
              "a broken file never errors on the island")
        module.stop()
    }

    static func opens() async {
        let rig = Rig()
        var bad = ThreadsFixtures.approval
        bad.thread = "a/b"
        rig.write(ThreadsFixtures.json(rows: [ThreadsFixtures.question, bad]))
        let presenter = ThreadsRecorder()
        let (module, context) = rig.start(presenter)
        await module.reload().value
        presenter.taps["threads.batch"]?()
        check(presenter.shown == [ThreadsPage.id], "the batch notice opens the page")
        let rows = presenter.rows
        check(rows[1].id == nil, "a row with no safe link is not a button")
        presenter.action?(rows[0].id ?? "")
        check(rig.opened.map(\.absoluteString) == ["t3code://threads/env-one/thread-billing"], "a row opens its thread")
        context.commands.first?.run(context)
        check(rig.opened.count == 2 && context.commands.count == 1, "its command too; the unsafe one has none")
        presenter.statusTap?()
        check(presenter.shown.count == 2, "the count opens the page")
        module.open(URL(string: "https://example.com")!)
        check(rig.opened.count == 2, "nothing but a T3 link is opened")
        module.stop()
    }

    /// The one real wait: a dispatch source fires on its own, so the harness hears it, capped at 5 s.
    static func fileEvent() async {
        let rig = Rig()
        rig.write(ThreadsFixtures.json(rows: []))
        let presenter = ThreadsRecorder()
        let (module, _) = rig.start(presenter)
        await module.reload().value
        let before = presenter.pageCalls
        rig.write(ThreadsFixtures.json(rows: [ThreadsFixtures.question]))
        let deadline = ContinuousClock.now + .seconds(5)
        while presenter.notices.isEmpty, ContinuousClock.now < deadline {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(20))
        }
        check(presenter.pageCalls > before && presenter.notices.count == 1, "a write to the file is read without a poll")
        module.stop()
    }
}
