// notchcast-hosted-only
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
    var onHTMLRead: (() -> Void)?
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
    func htmlText() -> String? {
        onHTMLRead?()
        return entry("public.html").map { "html:" + utf8($0) }
    }

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
    board.onHTMLRead = nil
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
