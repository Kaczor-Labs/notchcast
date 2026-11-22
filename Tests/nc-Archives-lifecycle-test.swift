// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandNoticeQueue.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift Tinycast/Platform/ProcessExit.swift
// notchcast-sources: Tinycast/Platform/ExecutableLocator.swift
// notchcast-sources: Tinycast/Features/Notchcast/Archives/ArchivesAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/Archives/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Archives/Service/ArchivesModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Archives/Service/ArchivesEnvironment.swift
// notchcast-sources: Tinycast/Features/Notchcast/Archives/Service/ArchiveExtractor.swift
// notchcast-sources: Tinycast/Features/Notchcast/Archives/Service/ArchiveCompressor.swift
// notchcast-sources: Tinycast/Features/Notchcast/Archives/Service/ArchiveProcess.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift
// notchcast-sources: Tests/nc-Archives-module-fixture.swift

import Foundation
import Synchronization

@MainActor private var regressionsFailed = false

@MainActor
private func regression(_ condition: Bool, _ message: String) {
    guard !condition else { return }
    regressionsFailed = true
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
}

@MainActor
func closesStopQuestionOnCompletion() async throws {
    let rig = try Rig()
    defer { rig.finish() }
    rig.tools.state.withLock { $0.hold = ["Slow.zip"] }
    rig.record.hold = true
    rig.module!.open([rig.archive("Slow.zip", listing: twoFiles)])
    while !rig.tools.state.withLock({ $0.heldStarted }) { await Task.yield() }
    rig.presenter.posts[0].onTap?()
    while !rig.record.hasQuestion { await Task.yield() }
    rig.tools.release()
    await rig.module!.drain()
    regression(rig.record.closed == 1, "extraction closes its Stop question on completion")
    rig.record.answerQuestion(false)
    check(rig.presenter.texts.last == "Extracted Slow" && rig.exists("Slow/b/c.txt"), "extraction still finishes")
}

@MainActor
func cancelsInPlaceQuestion(lateYes: Bool = false, switchOff: Bool = false) async throws {
    let rig = try Rig()
    defer { rig.finish() }
    rig.tools.state.withLock { ($0.extractStatuses, $0.partialFile) = ([3], "partial.txt") }
    rig.record.hold = true
    rig.record.ignoresCancel = lateYes
    rig.module!.open([rig.archive("Big.zip", listing: twoFiles)])
    while !rig.record.hasQuestion { await Task.yield() }
    check(rig.record.questions.first?.hasPrefix("Not enough space to keep Big.zip") == true, "asked to extract in place")
    let task = rig.module!.current!.task
    if switchOff {
        rig.controller.preferences.set("archives", on: false)
        while rig.module != nil { await Task.yield() }
    } else { rig.module!.cancelAll() }
    if lateYes { rig.record.answerQuestion(true) }
    await task.value
    guard lateYes else {
        return check(rig.record.closed == 1, "the in-place question closes on \(switchOff ? "switch-off" : "Cancel All")")
    }
    regression(rig.presenter.texts.last == "Stopped extracting Big.zip" && rig.visible == ["Big.zip"],
               "late Extract in Place yes after Cancel All leaves only Big.zip"
                   + " (notices \(rig.presenter.texts), files \(rig.visible))")
}

@MainActor
func cancelAndResume() async throws {
    let rig = try Rig()
    defer { rig.finish() }
    rig.tools.state.withLock { $0.hold = ["Slow.zip"] }
    rig.module!.open([rig.archive("Slow.zip", listing: twoFiles), rig.archive("Next.zip", listing: twoFiles)])
    while !rig.tools.state.withLock({ $0.heldStarted }) { await Task.yield() }
    rig.presenter.posts[0].onTap?()
    while rig.record.questions.isEmpty { await Task.yield() }
    check(rig.record.questions[0].hasPrefix("Stop extracting Slow.zip?"), "tapping the progress asks first")
    while rig.module!.current?.job.name == "Slow.zip" { await Task.yield() }
    await rig.module!.drain()
    check(rig.calls.contains { $0[1] == "restore" }, "a stopped HatchZip job drops its progress")
    check(rig.presenter.texts.contains("Stopped extracting Slow.zip") && rig.exists("Next"), "the queue goes on")
    check(!rig.exists("Slow") && rig.exists("Slow.zip"), "a kept archive stays and nothing half-done is placed")
    check(rig.journal().isEmpty, "\(rig.journal())")
}

@MainActor
func switchOffDuringExtraction() async throws {
    let rig = try Rig()
    defer { rig.finish() }
    let archive = rig.archive("Big.zip", listing: twoFiles)
    let module = rig.module!
    module.open([archive])
    await module.drain()
    check(rig.presenter.queue.notice?.text == "Extracted Big", "the first extraction succeeds")
    try FileManager.default.removeItem(at: rig.folder.appending(path: "Big"))

    rig.tools.state.withLock { $0.hold = ["Big.zip"] }
    module.open([archive])
    while !rig.tools.state.withLock({ $0.heldStarted }) { await Task.yield() }
    let running = module.current!
    check(FileManager.default.fileExists(atPath: running.job.staging.appending(path: "partial.txt").path),
          "the tool has written partial output")
    rig.defaults.set(true, forKey: "archivesDefaultApp")
    rig.controller.preferences.set("archives", on: false)
    while rig.module != nil { await Task.yield() }
    let afterSwitchOff = rig.presenter.queue.notice?.text
    await running.task.value
    check(afterSwitchOff != "Extracted Big", "switching Archives off revealed stale success: \(afterSwitchOff ?? "none")")
    check(rig.presenter.texts == ["Extracting Big.zip", "Extracted Big", "Extracting Big.zip", "Stopped extracting Big.zip"],
          "the interrupted run posts only a stopped result: \(rig.presenter.texts)")
    check(rig.presenter.queue.notice?.text == "Stopped extracting Big.zip", "the island shows the stopped result")
    check(rig.visible == ["Big.zip"], "switching off leaves only the kept archive: \(rig.visible)")
    check(rig.record.defaultApp == [false], "switched off, the archive types go back")
    check(rig.journal().map(\.name) == ["Big.zip"], "a switch-off keeps the job to resume")

    rig.tools.state.withLock { $0.hold = [] }
    rig.controller.preferences.set("archives", on: true)
    while rig.module == nil { await Task.yield() }
    await rig.module!.drain()
    check(rig.visible == ["Big", "Big.zip"] && rig.exists("Big/b/c.txt"), "re-enabling extracts from clean staging")
    check(!rig.exists("Big/partial.txt"), "the interrupted run's partial output is gone")
    check(rig.journal().isEmpty, "the job leaves the journal after success")
}

@MainActor
func reenableBeforeToolExits() async throws {
    let rig = try Rig()
    defer { rig.finish() }
    rig.tools.state.withLock {
        $0.hold = ["Big.zip"]
        $0.holdThroughCancellation = true
    }
    rig.module!.open([rig.archive("Big.zip", listing: twoFiles)])
    while !rig.tools.state.withLock({ $0.heldStarted }) { await Task.yield() }
    let running = rig.module!.current!
    rig.controller.preferences.set("archives", on: false)
    while rig.module != nil { await Task.yield() }
    rig.controller.preferences.set("archives", on: true)
    while rig.module == nil { await Task.yield() }
    check(rig.module?.current?.job.id == running.job.id, "re-enabling waits for the interrupted run")
    rig.tools.state.withLock {
        $0.hold = []
        $0.held?.resume()
        $0.held = nil
    }
    await rig.module!.drain()
    check(rig.presenter.texts == [
        "Extracting Big.zip", "Stopped extracting Big.zip", "Extracting Big.zip", "Extracted Big",
    ], "late success cannot finish a cancelled run: \(rig.presenter.texts)")
    check(rig.visible == ["Big", "Big.zip"] && !rig.exists("partial.txt"), "only the clean retry is published")
}

@MainActor
func defaultApp() async throws {
    let rig = try Rig(switchOn: false)
    defer { rig.finish() }
    rig.defaults.set(true, forKey: "archivesDefaultApp")
    rig.controller.preferences.set("archives", on: true)
    while rig.module == nil { await Task.yield() }
    check(rig.record.defaultApp == [true], "with the option on, switching the add-on on claims the archive types")
    rig.controller.stop()
    check(rig.record.defaultApp == [true], "quitting the app keeps them")

    var relaunch = try Rig(suite: rig.suite)
    check(relaunch.record.defaultApp.isEmpty, "a launch never claims again, so a Finder choice made since stays")
    relaunch.module!.setDefaultApp(false)
    relaunch.module!.setDefaultApp(true)
    check(relaunch.record.defaultApp == [false, true], "turning the option on claims at that moment")
    relaunch.finish(keepingDefaults: true)
    relaunch = try Rig(suite: rig.suite)
    check(relaunch.record.defaultApp.isEmpty, "and the next launch leaves it alone too")
    relaunch.finish(keepingDefaults: true)
}

@main
enum ArchivesLifecycleTest {
    @MainActor
    static func main() async throws {
        try await closesStopQuestionOnCompletion()
        try await cancelsInPlaceQuestion(lateYes: true)
        try await cancelsInPlaceQuestion()
        try await cancelsInPlaceQuestion(switchOff: true)
        try await cancelAndResume()
        try await switchOffDuringExtraction()
        try await reenableBeforeToolExits()
        try await defaultApp()
        if regressionsFailed { exit(EXIT_FAILURE) }
        print("nc-Archives-lifecycle-test: ok")
    }
}
