// notchcast-hosted-only
// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Notchcast/PastePlainText/PastePlainTextAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/PastePlainText/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/PastePlainText/Service/PastePlainTextModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/PastePlainText/Service/PastePlainTextSystem.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift

import CoreGraphics
import Foundation

// The shipped `live` is left out: this one stands in, so `makeModule` runs as shipped.

/// A pasteboard whose change count moves on every write, as `NSPasteboard` does.
@MainActor
final class FakeBoard: PlainPasteBoard {
    var items: [[PlainPasteEntry]] = []
    var changeCount = 0
    var ownWrites = 0
    var rtfReads = 0
    /// Its data reads nil, as a lazy provider that fails does.
    var nilType: String?
    /// Another app copies while the snapshot is being read.
    var bumpsDuringRead = false
    /// Another app copies right after the text is read, before the snapshot.
    var bumpsAfterText = false
    /// Writes that clear the board and then fail.
    var writeFailures = 0
    let ownMarker = "com.tinycast.internal"

    var types: [String] { items.flatMap { $0.map(\.type) } }
    var string: String? {
        defer { if bumpsAfterText { changeCount += 1 } }
        return entry("public.utf8-plain-text").map { utf8($0) }
    }
    func rtfText() -> String? {
        rtfReads += 1
        return entry("public.rtf").map { "rtf:" + utf8($0) }
    }
    func rtfdText() -> String? { entry("com.apple.flat-rtfd").map { "rtfd:" + utf8($0) } }
    func htmlText() -> String? { entry("public.html").map { "html:" + utf8($0) } }

    var itemTypes: [[String]] { items.map { $0.map(\.type) } }

    func data(item: Int, type: String) -> Data? {
        if bumpsDuringRead { changeCount += 1 }
        guard type != nilType else { return nil }
        return items[item].first { $0.type == type }?.data
    }

    func write(_ items: [[PlainPasteEntry]], ifChangeCount expected: Int) -> PlainPasteWrite {
        guard changeCount == expected else { return .superseded }
        guard writeFailures == 0 else {
            writeFailures -= 1
            return .failed(changeCount: replace([]))
        }
        ownWrites += 1
        return .written(changeCount: replace(items))
    }

    /// Someone else copying: history would record this one.
    @discardableResult
    func copy(_ pairs: [(String, String)]...) -> Int {
        replace(pairs.map { $0.map { PlainPasteEntry(type: $0.0, data: Data($0.1.utf8)) } })
    }

    private func replace(_ new: [[PlainPasteEntry]]) -> Int {
        items = new
        changeCount += 1
        return changeCount
    }

    private func utf8(_ data: Data) -> String { String(bytes: data, encoding: .utf8) ?? "" }

    private func entry(_ type: String) -> Data? { items.lazy.flatMap { $0 }.first { $0.type == type }?.data }
}

final class FakeTimer: PlainPasteTimer {
    let delay: Duration
    let due: ContinuousClock.Instant
    let work: @MainActor () -> Void
    var isCancelled = false

    init(delay: Duration, due: ContinuousClock.Instant, work: @escaping @MainActor () -> Void) {
        self.delay = delay
        self.due = due
        self.work = work
    }

    func cancel() { isCancelled = true }
}

/// Time moves only when a timer fires or a test sleeps the Mac.
@MainActor
final class FakeSystem {
    let board = FakeBoard()
    var pastes: [String?] = []
    var timers: [FakeTimer] = []
    var history: [String] = []
    var now = ContinuousClock.now
    /// Polls that still find the hotkey's keys down.
    var heldPolls = 0
    var hasMatchStyle = false
    var matchStylePresses = 0

    var live: [FakeTimer] { timers.filter { !$0.isCancelled } }

    func schedule(_ delay: Duration, _ work: @escaping @MainActor () -> Void) -> FakeTimer {
        let timer = FakeTimer(delay: delay, due: now + delay, work: work)
        timers.append(timer)
        return timer
    }

    /// Runs the earliest live timer at its due time.
    func fire() {
        guard let next = live.min(by: { $0.due < $1.due }) else { preconditionFailure("no timer to fire") }
        timers.removeAll { $0 === next }
        now = max(now, next.due)
        next.work()
    }

    func fireAll() {
        while !live.isEmpty { fire() }
    }
}

@MainActor let fake = FakeSystem()

extension PastePlainTextSystem {
    static let live = PastePlainTextSystem(
        makeBoard: { fake.board },
        postCommandV: { fake.pastes.append(fake.board.string ?? fake.board.items.first?.first?.type) },
        modifiersHeld: {
            guard fake.heldPolls > 0 else { return false }
            fake.heldPolls -= 1
            return true
        },
        pressMatchStyle: {
            fake.matchStylePresses += 1
            return fake.hasMatchStyle
        },
        now: { fake.now },
        after: { fake.schedule($0, $1) }
    )
}

final class FakeSession: NotchcastTapSession {
    let mask: CGEventMask
    let options: CGEventTapOptions
    let router: NotchcastTapRouter
    var isRunning = true

    init(_ request: NotchcastTapSessionRequest) {
        mask = request.mask
        options = request.options
        router = request.router
    }

    func stop() { isRunning = false }
}

@MainActor
final class RecordingPresenter: IslandPresenting {
    var posts: [IslandNotice] = []
    func showLevel(_ level: IslandLevel) {}
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) { posts.append(notice) }
    func end(notice id: String) {}
    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {}
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
}

@MainActor var trusted = true

@MainActor
final class Rig {
    let suite = "nc-PastePlainText-module-test.\(UUID())"
    let defaults: UserDefaults
    let presenter = RecordingPresenter()
    let controller: NotchcastController

    init(on: Bool) {
        defaults = UserDefaults(suiteName: suite)!
        if on { defaults.set(true, forKey: "pastePlain") }
        let hub = NotchcastTapHub(syntheticTag: 0x54494E59, isTrusted: { trusted }, makeSession: { FakeSession($0) })
        controller = NotchcastController(
            addons: [PastePlainTextAddon.self], defaults: defaults, hub: hub, dictation: FakeDictation(),
            services: NotchcastServices(
                clipboard: NotchcastClipboardMutation(
                    prepare: { fake.history.append("prepare \(fake.board.changeCount)") },
                    synchronize: { fake.history.append("sync \($0)") })),
            presenter: presenter)
        controller.start()
    }

    @discardableResult
    func run() -> Bool { controller.run(entryID: "command:nc-paste-plain-text") }

    func finish() {
        controller.stop()
        UserDefaults().removePersistentDomain(forName: suite)
    }
}

@MainActor
func reset() {
    let board = fake.board
    board.items = []
    board.ownWrites = 0
    board.rtfReads = 0
    board.nilType = nil
    board.bumpsDuringRead = false
    board.bumpsAfterText = false
    board.writeFailures = 0
    fake.pastes = []
    fake.timers = []
    fake.history = []
    fake.heldPolls = 0
    fake.hasMatchStyle = false
    fake.matchStylePresses = 0
    trusted = true
}

let styled: [(String, String)] = [("public.html", "<b>Hi</b>"), ("public.rtf", "Hi"), ("public.utf8-plain-text", "Hi")]
let plainHi: [[PlainPasteEntry]] = [[
    .init(type: "public.utf8-plain-text", data: Data("Hi".utf8)), .init(type: "com.tinycast.internal", data: Data()),
]]

@main
enum PastePlainTextModuleTests {
    @MainActor
    static func main() {
        engine()
        snapshotRefusal()
        writeFailure()
        wiring()
        readGap()
        nativeRoute()
        heldKeys()
        keystrokeGuard()
        secondPress()
        print("nc-PastePlainText-module-test: OK")
    }

    @MainActor
    static func makeEngine() -> PlainPasteEngine {
        PlainPasteEngine(
            board: fake.board, prepareWrite: { fake.history.append("prepare \(fake.board.changeCount)") },
            didWrite: { fake.history.append("sync \($0)") })
    }

    @MainActor
    static func lend(_ engine: PlainPasteEngine) -> PlainPasteEngine.Outcome {
        let changeCount = engine.changeCount
        guard let text = engine.text() else { preconditionFailure("the clipboard holds text") }
        return engine.lend(text, readAt: changeCount)
    }

    @MainActor
    static func engine() {
        reset()
        let board = fake.board
        let engine = makeEngine()
        let copied = board.copy(styled)
        let original = board.items
        guard case .plain(let written) = lend(engine) else { preconditionFailure("styled text pastes plain") }
        precondition(board.items == plainHi, "only the plain text is on the clipboard, marked as our own")
        precondition(fake.history == ["prepare \(copied)", "sync \(written)"],
                     "history reads the user's copy before the write and is baselined on the write")
        engine.restorePending()
        precondition(board.items == original, "every item and type comes back, with no marker added")
        precondition(fake.history.last == "sync \(board.changeCount)", "and history is baselined on the restore")
        precondition(!engine.isRestorePending, "the restore is done")
        engine.restorePending()
        precondition(board.ownWrites == 2, "a repeated restore writes nothing twice")

        guard case .plain = lend(engine) else { preconditionFailure("pastes again") }
        board.copy([("public.utf8-plain-text", "New")])
        let entries = fake.history.count
        engine.restorePending()
        precondition(board.string == "New" && !engine.isRestorePending, "a copy made before the restore is kept")
        precondition(fake.history.count == entries, "and history is left to record it")

        board.copy([("public.rtf", "R")])
        guard case .plain = lend(engine) else { preconditionFailure("RTF pastes plain") }
        precondition(board.string == "rtf:R", "the RTF's text is written")
        engine.restorePending()
        precondition(board.items == [[.init(type: "public.rtf", data: Data("R".utf8))]], "the original is back")

        board.copy([("public.file-url", "file:///a"), ("public.utf8-plain-text", "a")])
        precondition(engine.text() == nil, "file URLs are left to a normal ⌘V")
    }

    @MainActor
    static func snapshotRefusal() {
        reset()
        let board = fake.board
        let engine = makeEngine()
        board.copy(styled)
        let original = board.items
        board.nilType = "public.html"
        precondition(lend(engine) == .refused, "a type with no data refuses the paste")
        precondition(board.items == original && board.ownWrites == 0, "and the board is untouched")
        board.nilType = nil
        board.bumpsDuringRead = true
        precondition(lend(engine) == .refused, "a copy made during the read refuses the paste")
        precondition(board.ownWrites == 0 && !engine.isRestorePending, "and nothing is written")
        board.bumpsDuringRead = false
        board.copy([("public.utf8-plain-text", "Old")])
        board.bumpsAfterText = true
        precondition(lend(engine) == .refused, "a copy between the text read and the snapshot refuses the paste")
        precondition(board.ownWrites == 0 && !engine.isRestorePending, "so the older text is never pasted")
    }

    @MainActor
    static func writeFailure() {
        reset()
        let board = fake.board
        let engine = makeEngine()
        board.copy(styled)
        let original = board.items
        guard case .plain = lend(engine) else { preconditionFailure("pastes plain") }
        board.writeFailures = 1
        engine.restorePending()
        precondition(engine.isRestorePending, "a failed restore keeps the original for one retry")
        engine.restorePending()
        precondition(board.items == original && !engine.isRestorePending, "and the retry puts it back")

        guard case .plain = lend(engine) else { preconditionFailure("pastes plain again") }
        board.writeFailures = 2
        engine.restorePending()
        engine.restorePending()
        precondition(!engine.isRestorePending, "a second failure gives up")

        board.copy(styled)
        board.writeFailures = 1
        precondition(lend(engine) == .refused, "a failed temporary write refuses the paste")
        precondition(board.items == original && !engine.isRestorePending, "and puts the original back")
        precondition(fake.history.last == "sync \(board.changeCount)", "baselining history on it")
    }

    @MainActor
    static func readGap() {
        reset()
        let rig = Rig(on: true)
        fake.board.copy(styled)
        fake.board.bumpsAfterText = true
        precondition(rig.run(), "on: the command runs")
        fake.fireAll()
        precondition(fake.pastes.isEmpty && fake.board.ownWrites == 0,
                     "a copy landing right after the text read pastes nothing, never the older text")
        rig.finish()
    }

    @MainActor
    static func wiring() {
        reset()
        var rig = Rig(on: false)
        precondition(!rig.run(), "off by default: the command does not run")
        precondition(fake.pastes.isEmpty, "nothing pasted while off")
        rig.finish()

        rig = Rig(on: true)
        let copied = fake.board.copy(styled)
        let original = fake.board.items
        precondition(rig.run(), "on: the command runs")
        precondition(fake.pastes.isEmpty && fake.board.items == original, "nothing is touched before focus is back")
        precondition(fake.live.map(\.delay) == [.milliseconds(80)], "for 80 ms")
        fake.fire()
        precondition(fake.matchStylePresses == 1, "the app's own matching-style paste is tried first")
        precondition(fake.pastes.isEmpty && fake.board.items == plainHi, "without one, the plain text is lent")
        precondition(fake.live.map(\.delay) == [.milliseconds(60)], "and ⌘V waits a beat after the keys are up")
        fake.fire()
        precondition(fake.pastes == ["Hi"], "plain text pasted")
        precondition(fake.live.map(\.delay) == [.milliseconds(500)], "the restore waits 0.5 s after ⌘V")
        fake.fire()
        precondition(fake.board.items == original, "the timer restores the original")
        precondition(fake.history == ["prepare \(copied)", "sync \(copied + 1)", "sync \(copied + 2)"],
                     "history drains first, then is baselined on both writes")

        rig.run()
        fake.fire()
        fake.fire()
        rig.controller.stop()
        precondition(fake.board.items == original, "stopping the module finishes a pending restore")
        precondition(fake.live.isEmpty, "and calls off its timers")
        rig.finish()

        reset()
        rig = Rig(on: true)
        fake.hasMatchStyle = true
        fake.board.copy([("public.png", "png"), ("public.utf8-plain-text", "https://example.com/a.png")])
        rig.run()
        fake.fireAll()
        precondition(fake.pastes == ["https://example.com/a.png"] && fake.board.ownWrites == 0,
                     "a lone picture sends a normal ⌘V alone")
        precondition(fake.matchStylePresses == 0, "never the matching-style paste, which would paste its link")
        rig.finish()

        reset()
        rig = Rig(on: true)
        fake.board.copy(styled)
        fake.board.nilType = "public.rtf"
        rig.run()
        fake.fire()
        precondition(fake.live.isEmpty && fake.board.ownWrites == 0, "an unreadable clipboard pastes nothing")
        precondition(rig.presenter.posts.last?.isFailure == true, "and a failure notice says so")
        rig.finish()

        reset()
        rig = Rig(on: true)
        trusted = false
        fake.board.copy(styled)
        rig.run()
        precondition(fake.timers.isEmpty && fake.board.ownWrites == 0, "without Accessibility nothing is touched")
        precondition(rig.presenter.posts.last?.isFailure == true, "and a failure notice says why")
        rig.finish()
    }

    /// The app's own ⌥⇧⌘V carries the paste, so the clipboard is never written.
    @MainActor
    static func nativeRoute() {
        reset()
        let rig = Rig(on: true)
        fake.hasMatchStyle = true
        fake.heldPolls = 50
        fake.board.copy(styled)
        let original = fake.board.items
        rig.run()
        fake.fire()
        precondition(fake.matchStylePresses == 1 && fake.pastes.isEmpty, "the menu item is pressed, no ⌘V sent")
        precondition(fake.board.items == original && fake.board.ownWrites == 0 && fake.live.isEmpty,
                     "the clipboard is never touched and held keys do not matter")
        precondition(fake.history.isEmpty, "and history sees nothing")
        rig.finish()
    }

    /// ⌘V waits until the hotkey's keys are up, so it never lands as another chord.
    @MainActor
    static func heldKeys() {
        reset()
        var rig = Rig(on: true)
        fake.board.copy(styled)
        let original = fake.board.items
        fake.heldPolls = 3
        rig.run()
        fake.fire()
        for _ in 0..<3 {
            precondition(fake.live.map(\.delay) == [.milliseconds(15)] && fake.pastes.isEmpty,
                         "no ⌘V while the keys are held, polled every 15 ms")
            fake.fire()
        }
        precondition(fake.live.map(\.delay) == [.milliseconds(60)] && fake.pastes.isEmpty, "then a beat")
        fake.fireAll()
        precondition(fake.pastes == ["Hi"] && fake.board.items == original, "then one paste, original back")

        fake.pastes = []
        fake.heldPolls = 80
        rig.run()
        fake.fireAll()
        precondition(fake.pastes == ["Hi"], "a slow release past a second still pastes once")
        rig.finish()

        reset()
        rig = Rig(on: true)
        fake.board.copy([("public.file-url", "file:///a")])
        fake.heldPolls = 2
        rig.run()
        fake.fire()
        fake.fire()
        fake.fire()
        precondition(fake.pastes.isEmpty && fake.live.map(\.delay) == [.milliseconds(60)],
                     "a normal paste waits for the keys too")
        fake.fire()
        precondition(fake.pastes == ["public.file-url"] && fake.board.ownWrites == 0, "and touches nothing")
        rig.finish()
    }

    /// ⌘V goes out only into the board and the moment it was meant for.
    @MainActor
    static func keystrokeGuard() {
        reset()
        let rig = Rig(on: true)
        fake.board.copy(styled)
        rig.run()
        fake.board.copy([("public.utf8-plain-text", "Secret")])
        fake.fire()
        precondition(fake.pastes.isEmpty, "a copy made during the focus delay is never pasted")
        precondition(fake.board.string == "Secret" && fake.live.isEmpty, "and is left on the clipboard")

        fake.board.copy(styled)
        let original = fake.board.items
        rig.run()
        fake.now += .seconds(30)
        fake.fire()
        precondition(fake.pastes.isEmpty && fake.live.isEmpty, "a focus delay a sleep stretched sends no ⌘V")

        rig.run()
        fake.fire()
        fake.now += .seconds(30)
        fake.fire()
        precondition(fake.pastes.isEmpty, "nor does a wait for the keys a sleep stretched")
        precondition(fake.board.items == original, "and the original comes straight back")

        rig.run()
        fake.fire()
        fake.board.copy([("public.utf8-plain-text", "Mid")])
        fake.fire()
        precondition(fake.pastes.isEmpty && fake.board.string == "Mid", "a copy made during the wait is never pasted")

        fake.board.copy(styled)
        rig.run()
        fake.fire()
        rig.controller.stop()
        precondition(fake.board.items == original && fake.live.isEmpty, "stop calls off a ⌘V not yet sent")
        fake.board.copy([("public.utf8-plain-text", "Newer")])
        for timer in fake.timers { timer.work() }
        precondition(fake.pastes.isEmpty && fake.board.string == "Newer", "and an orphaned timer touches nothing")
        rig.finish()
    }

    /// A second press never restores under a ⌘V the target may still be reading.
    @MainActor
    static func secondPress() {
        reset()
        let rig = Rig(on: true)
        fake.board.copy(styled)
        let original = fake.board.items
        rig.run()
        fake.fire()
        fake.fire()
        fake.now += .milliseconds(100)
        rig.run()
        precondition(fake.board.items == plainHi && fake.pastes == ["Hi"], "the first ⌘V's plain text stays put")
        precondition(fake.live.map(\.delay) == [.milliseconds(400)], "until the rest of its settle")
        fake.fire()
        precondition(fake.board.items == original && fake.live.map(\.delay) == [.milliseconds(80)],
                     "then the original is restored and pasted plain again")
        fake.fireAll()
        precondition(fake.pastes == ["Hi", "Hi"] && fake.board.items == original, "two pastes, original back")

        rig.run()
        rig.run()
        precondition(fake.live.count == 1, "a press before ⌘V went out replaces it")
        fake.fireAll()
        precondition(fake.pastes == ["Hi", "Hi", "Hi"] && fake.board.items == original, "one more paste, original back")
        rig.finish()
    }
}
