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
// notchcast-sources: Tests/nc-PastePlainText-fixture.swift

import Foundation

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
        heldKeysTimeout()
        keystrokeGuard()
        secondPress()
        reenteredPress()
        reenteredPressFiresDuringRead()
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

    @MainActor
    static func heldKeysTimeout() {
        reset()
        let rig = Rig(on: true)
        fake.board.copy(styled)
        let original = fake.board.items
        fake.heldPolls = 1000

        rig.run()
        fake.fire()
        for _ in 0..<100 {
            precondition(fake.live.map(\.delay) == [.milliseconds(15)] && fake.pastes.isEmpty,
                         "the held hotkey gets 100 waits of 15 ms before ⌘V")
            fake.fire()
        }
        precondition(fake.live.map(\.delay) == [.milliseconds(60)] && fake.pastes.isEmpty,
                     "⌘V settles for 60 ms even with the hotkey still held")
        fake.fire()
        precondition(fake.pastes == ["Hi"] && fake.live.map(\.delay) == [.milliseconds(500)],
                     "one ⌘V goes out, then the restore is scheduled")
        fake.fire()
        precondition(fake.board.items == original && fake.live.isEmpty, "the original clipboard is restored")
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

    @MainActor
    static func reenteredPress() {
        reset()
        let rig = Rig(on: true)
        fake.board.copy([("public.html", "Hi")])
        let original = fake.board.items
        fake.board.onHTMLRead = {
            fake.board.onHTMLRead = nil
            rig.run()
        }

        rig.run()
        precondition(fake.live.count == 1, "re-entry during HTML import left \(fake.live.count) live timers")
        fake.fireAll()
        precondition(fake.pastes == ["html:Hi"] && fake.board.items == original, "one paste, original restored")
        rig.finish()
    }

    @MainActor
    static func reenteredPressFiresDuringRead() {
        reset()
        let rig = Rig(on: true)
        defer { rig.finish() }
        fake.board.copy([("public.html", "Hi")])
        let original = fake.board.items
        fake.board.onHTMLRead = {
            fake.board.onHTMLRead = nil
            rig.run()
            precondition(fake.live.map(\.delay) == [.milliseconds(80)], "the second press schedules its focus timer")
            fake.fire()
            precondition(fake.live.map(\.delay) == [.milliseconds(60)] && fake.board.items != original,
                         "the second press lends the plain text before the first read returns")
        }

        rig.run()
        fake.fireAll()
        precondition(fake.pastes == ["html:Hi"], "FAIL: the second press's paste was dropped during HTML import")
        precondition(fake.board.items == original, "the original clipboard is restored after the paste")
    }
}
