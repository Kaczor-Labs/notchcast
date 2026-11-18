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

    var hasFileURLs: Bool { entry("public.file-url") != nil }
    var string: String? { entry("public.utf8-plain-text").map { utf8($0) } }
    func rtfText() -> String? {
        rtfReads += 1
        return entry("public.rtf").map { "rtf:" + utf8($0) }
    }
    func rtfdText() -> String? { entry("com.apple.flat-rtfd").map { "rtfd:" + utf8($0) } }
    func snapshot() -> [[PlainPasteEntry]] { items }

    func writeOwn(_ text: String) -> Int {
        ownWrites += 1
        return replace([[.init(type: "public.utf8-plain-text", data: Data(text.utf8))]])
    }

    func restoreOwn(_ items: [[PlainPasteEntry]]) -> Int {
        ownWrites += 1
        return replace(items)
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

@MainActor
final class FakeSystem {
    let board = FakeBoard()
    var pastes: [String?] = []
    var timers: [(delay: Duration, work: @MainActor () -> Void)] = []

    func fire() {
        let due = timers
        timers = []
        for timer in due { timer.work() }
    }
}

@MainActor let fake = FakeSystem()

extension PastePlainTextSystem {
    static let live = PastePlainTextSystem(
        makeBoard: { fake.board },
        sendPaste: { fake.pastes.append(fake.board.string ?? fake.board.items.first?.first?.type) },
        after: { fake.timers.append(($0, $1)) }
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
            addons: [PastePlainTextAddon.self], defaults: defaults, hub: hub,
            dictation: FakeDictation(), presenter: presenter)
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
    fake.board.items = []
    fake.board.ownWrites = 0
    fake.board.rtfReads = 0
    fake.pastes = []
    fake.timers = []
    trusted = true
}

let styled: [(String, String)] = [("public.html", "<b>Hi</b>"), ("public.rtf", "Hi"), ("public.utf8-plain-text", "Hi")]

@main
enum PastePlainTextModuleTests {
    @MainActor
    static func main() {
        selection()
        restoreGuard()
        wiring()
        print("nc-PastePlainText-module-test: OK")
    }

    @MainActor
    static func selection() {
        let none: () -> String? = { nil }
        precondition(PlainPasteEngine.text(hasFileURLs: false, string: "a", rtf: { "b" }, rtfd: { "c" }) == "a",
                     "the plain string wins")
        precondition(PlainPasteEngine.text(hasFileURLs: false, string: nil, rtf: { "b" }, rtfd: { "c" }) == "b",
                     "RTF when no string")
        precondition(PlainPasteEngine.text(hasFileURLs: false, string: "", rtf: none, rtfd: { "c" }) == "c",
                     "RTFD when neither string nor RTF")
        precondition(PlainPasteEngine.text(hasFileURLs: true, string: "a", rtf: none, rtfd: none) == nil,
                     "file URLs fall back to a normal paste")
        precondition(PlainPasteEngine.text(hasFileURLs: false, string: nil, rtf: none, rtfd: none) == nil,
                     "no text falls back to a normal paste")
        precondition(PlainPasteEngine.text(
            hasFileURLs: false, string: "a", rtf: { preconditionFailure("RTF read beside a string") }, rtfd: none) == "a",
                     "RTF is never converted when a string is there")
    }

    @MainActor
    static func restoreGuard() {
        reset()
        let board = fake.board
        let engine = PlainPasteEngine(board: board, sendPaste: { fake.pastes.append(board.string) })
        board.copy(styled)
        let original = board.items
        guard case .plain(let first) = engine.paste() else { preconditionFailure("styled text pastes plain") }
        precondition(board.items == [[.init(type: "public.utf8-plain-text", data: Data("Hi".utf8))]],
                     "only the plain text is on the clipboard while ⌘V lands")
        precondition(fake.pastes == ["Hi"], "⌘V goes out once, after the write")
        engine.restore(token: first)
        precondition(board.items == original, "every item and type comes back")
        precondition(!engine.isRestorePending, "the restore is done")
        engine.restore(token: first)
        precondition(board.ownWrites == 2, "a repeated timer restores nothing twice")

        guard case .plain(let second) = engine.paste() else { preconditionFailure("pastes again") }
        board.copy([("public.utf8-plain-text", "New")])
        engine.restore(token: second)
        precondition(board.string == "New", "a copy made before the restore is never overwritten")

        board.copy([("public.rtf", "R")])
        guard case .plain(let third) = engine.paste() else { preconditionFailure("RTF pastes plain") }
        precondition(board.string == "rtf:R", "the RTF's text is written")
        guard case .plain(let fourth) = engine.paste() else { preconditionFailure("second press pastes") }
        precondition(fake.pastes.last == "rtf:R", "the second press read the restored original, not its own write")
        engine.restore(token: third)
        precondition(engine.isRestorePending, "the first press's timer leaves the second press's restore alone")
        engine.restore(token: fourth)
        precondition(board.items == [[.init(type: "public.rtf", data: Data("R".utf8))]], "the original is back")

        board.copy([("public.file-url", "file:///a"), ("public.utf8-plain-text", "a")])
        let writes = board.ownWrites
        precondition(engine.paste() == .passThrough, "file URLs send a normal ⌘V")
        precondition(board.ownWrites == writes && !engine.isRestorePending, "and leave the clipboard alone")
        board.copy([("public.png", "png")])
        precondition(engine.paste() == .passThrough, "no text sends a normal ⌘V")
    }

    @MainActor
    static func wiring() {
        reset()
        var rig = Rig(on: false)
        precondition(!rig.run(), "off by default: the command does not run")
        precondition(fake.pastes.isEmpty, "nothing pasted while off")
        rig.finish()

        rig = Rig(on: true)
        fake.board.copy(styled)
        let original = fake.board.items
        precondition(rig.run(), "on: the command runs")
        precondition(fake.pastes == ["Hi"], "plain text pasted")
        precondition(fake.timers.map(\.delay) == [.milliseconds(500)], "the restore waits 0.5 s")
        fake.fire()
        precondition(fake.board.items == original, "the timer restores the original")

        rig.run()
        rig.controller.stop()
        precondition(fake.board.items == original, "stopping the module finishes a pending restore")
        fake.fire()
        precondition(fake.board.items == original, "and the orphaned timer changes nothing")
        rig.finish()

        reset()
        rig = Rig(on: true)
        trusted = false
        fake.board.copy(styled)
        rig.run()
        precondition(fake.pastes.isEmpty && fake.board.ownWrites == 0, "without Accessibility nothing is touched")
        precondition(rig.presenter.posts.last?.isFailure == true, "and a failure notice says why")
        rig.finish()
    }
}
