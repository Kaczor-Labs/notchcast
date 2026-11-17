// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Features/Settings/SettingsTab.swift Tinycast/Features/Launcher/Model/CommandID.swift Tinycast/Features/HotKeys/Model/HotKeyAction.swift Tinycast/Features/HotKeys/Model/HotKeyAction+EntryID.swift Tinycast/Features/QuickActions/Model/QuickAction.swift
// notchcast-sources: Tinycast/Features/QuickActions/Model/BuiltInQuickAction.swift Tinycast/Features/QuickActions/Model/CustomQuickAction.swift Tinycast/Features/Quicklinks/Model/Quicklink.swift Tinycast/Features/Quicklinks/Model/QuicklinkDestination.swift Tinycast/Features/SystemActions/Model/SystemAction.swift
// notchcast-sources: Tinycast/Features/CustomCommands/Model/CustomCommand.swift Tinycast/Features/AppleShortcuts/Model/AppleShortcut.swift Tinycast/Features/Snippets/Model/Snippet.swift Tinycast/Features/WindowManagement/Model/WindowCommand.swift Tinycast/Features/WindowManagement/Model/WindowCycle.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/WindowPlacementEngine.swift Tinycast/Features/WindowManagement/Model/WindowLayoutAnchor.swift Tinycast/Features/WindowManagement/Model/WindowLayoutDisplay.swift Tinycast/Features/WindowManagement/Model/WindowLayout.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/WindowLayoutGeometry.swift Tinycast/Features/WindowManagement/Model/RoomLayoutKind.swift Tinycast/Features/WindowManagement/Model/RoomLayoutEngine.swift Tinycast/Features/WindowManagement/Model/RoomGrid.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/RoomWindow.swift Tinycast/Features/WindowManagement/Model/Room.swift Tinycast/Features/WindowManagement/Model/CustomWindowSize.swift Tinycast/Platform/LocalizedResource.swift Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift
import Foundation

private struct HelperCrash: LocalizedError {
    var errorDescription: String? { "helper crashed" }
}

@main
@MainActor
struct CoreTranscribeTest {
    static var failures = 0
    static var checks = 0
    static let audio = URL(fileURLWithPath: "/nonexistent/clip.m4a")

    static func check(_ label: String, _ ok: Bool) {
        checks += 1
        if !ok {
            failures += 1
            print("FAIL \(label)")
        }
    }

    static func outcome(_ runner: NotchcastTranscriptionRunner) async -> Result<String, any Error> {
        do { return .success(try await runner.transcribe(audio)) } catch { return .failure(error) }
    }

    static func failure(_ result: Result<String, any Error>) -> NotchcastTranscribeError? {
        if case .failure(let error) = result { return error as? NotchcastTranscribeError }
        return nil
    }

    /// Lets a started task reach its suspension point before the test pokes the fake.
    static func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    static func main() async {
        await passesThrough()
        await mapsErrors()
        await refusesWhileDictating()
        await refusesSecondCall()
        await userWaitsForCleanup()
        await voidsResultAcrossUserSession()
        await rechecksBeforeEachPiece()
        await cancelledCallerWhileBusy()
        await dropsCancelledResult()
        print(failures == 0 ? "PASS CoreTranscribeTest (\(checks) checks)" : "FAILED \(failures)/\(checks)")
        if failures > 0 { exit(1) }
    }

    static func passesThrough() async {
        let fake = FakeDictation()
        fake.result = .success("hello there")
        let result = await outcome(NotchcastTranscriptionRunner(dictation: fake))
        check("the transcript passes through", (try? result.get()) == "hello there")
        check("the hook gets the caller's file", fake.calls == [audio])
    }

    static func mapsErrors() async {
        let cases: [(any Error, NotchcastTranscribeError)] = [
            (NotchcastTranscribeError.unavailable, .unavailable),
            (NotchcastTranscribeError.busy, .busy),
            (NotchcastTranscribeError.unreadableAudio, .unreadableAudio),
            (NotchcastTranscribeError.failed("bad"), .failed("bad")),
            (HelperCrash(), .failed("helper crashed")),
        ]
        for (thrown, expected) in cases {
            let fake = FakeDictation()
            fake.result = .failure(thrown)
            let got = failure(await outcome(NotchcastTranscriptionRunner(dictation: fake)))
            check("\(thrown) reaches the add-on as \(expected)", got == expected)
        }
    }

    static func refusesWhileDictating() async {
        let fake = FakeDictation()
        fake.isDictating = true
        let got = failure(await outcome(NotchcastTranscriptionRunner(dictation: fake)))
        check("busy while the user dictates", got == .busy)
        check("the user's dictation is never touched", fake.calls.isEmpty)
    }

    static func refusesSecondCall() async {
        let fake = FakeDictation()
        fake.result = .success("first")
        fake.holds = true
        let runner = NotchcastTranscriptionRunner(dictation: fake)
        let first = Task { await outcome(runner) }
        await settle()
        let second = Task { await outcome(runner) }
        await settle()
        fake.release()
        check("a second concurrent call is busy", failure(await second.value) == .busy)
        check("the first call still finishes", (try? await first.value.get()) == "first")
        check("only the first call reached Dictation", fake.calls.count == 1)
        fake.holds = false
        fake.result = .success("again")
        check("the runner frees itself afterwards", (try? await outcome(runner).get()) == "again")
    }

    static func isCancellation(_ result: Result<String, any Error>) -> Bool {
        if case .failure(let error) = result { return error is CancellationError }
        return false
    }

    static func userWaitsForCleanup() async {
        let fake = FakeDictation()
        fake.result = .success("late")
        fake.holds = true
        let runner = NotchcastTranscriptionRunner(dictation: fake)
        let call = Task { await outcome(runner) }
        await settle()
        let user = Task { await fake.userDictates() }
        await settle()
        fake.release()
        check("the user's dictation is never refused busy", await user.value)
        check("ours ends busy once the user starts", failure(await call.value) == .busy)
    }

    static func voidsResultAcrossUserSession() async {
        let fake = FakeDictation()
        fake.result = .success("late")
        fake.holds = true
        fake.finishesDespiteCancel = true
        let runner = NotchcastTranscriptionRunner(dictation: fake)
        let call = Task { await outcome(runner) }
        await settle()
        let user = Task { await fake.userDictates() }
        await settle()
        fake.release()
        _ = await user.value
        check("the user's session has ended", !fake.isDictating)
        check("a session that started and ended mid-run voids our text", failure(await call.value) == .busy)
    }

    static func rechecksBeforeEachPiece() async {
        let fake = FakeDictation()
        fake.result = .success("late")
        fake.holds = true
        fake.pieces = 2
        let runner = NotchcastTranscriptionRunner(dictation: fake)
        let call = Task { await outcome(runner) }
        await settle()
        fake.isDictating = true
        fake.release()
        await settle()
        check("no piece enters the model once the user is dictating", fake.admittedPieces == 1)
        fake.release()
        check("the interrupted run is busy", failure(await call.value) == .busy)
    }

    static func cancelledCallerWhileBusy() async {
        let fake = FakeDictation()
        fake.holds = true
        let runner = NotchcastTranscriptionRunner(dictation: fake)
        let first = Task { await outcome(runner) }
        await settle()
        let late = Task { await outcome(runner) }
        late.cancel()
        check("a cancelled caller gets CancellationError, not busy", isCancellation(await late.value))
        fake.release()
        _ = await first.value
    }

    static func dropsCancelledResult() async {
        let fake = FakeDictation()
        fake.result = .success("unwanted")
        fake.holds = true
        fake.finishesDespiteCancel = true
        let runner = NotchcastTranscriptionRunner(dictation: fake)
        let call = Task { await outcome(runner) }
        await settle()
        call.cancel()
        await settle()
        fake.release()
        check("a cancelled caller gets no transcript", isCancellation(await call.value))
    }
}
