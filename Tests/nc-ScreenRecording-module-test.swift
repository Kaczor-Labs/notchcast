// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Notchcast/ScreenRecording/ScreenRecordingAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/ScreenRecording/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/ScreenRecording/Service/RecordingSystem.swift
// notchcast-sources: Tinycast/Features/Notchcast/ScreenRecording/Service/RecordingWorkFolder.swift
// notchcast-sources: Tinycast/Features/Notchcast/ScreenRecording/Service/ScreenRecordingModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/ScreenRecording/Service/ScreenRecordingRecovery.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift Tests/nc-ScreenRecording-fixture.swift

import Foundation

@main
@MainActor
enum ScreenRecordingModuleTests {
    static var failures = 0
    static var checks = 0

    static func check(_ name: String, _ value: Bool) {
        checks += 1
        if !value { failures += 1; print("FAIL \(name)") }
    }

    static func main() async {
        for folder in [desktopFolder, work, chosen] {
            precondition((try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil)
        }
        defer { try? FileManager.default.removeItem(at: scratch) }
        let rig = Rig()
        await descriptor(rig)
        await recordTrimSave(rig)
        await copyAndDiscard(rig)
        await screenAndToggle(rig)
        await refusals(rig)
        await endings(rig)
        await switchOff(rig)
        rig.finish()
        await recovery()
        print("\(checks) screen recording module checks; \(failures) failures")
        if failures > 0 { exit(1) }
        print("PASSED")
    }

    static func descriptor(_ rig: Rig) async {
        check("the v1 switch id", ScreenRecordingAddon.switches.map(\.id) == ["recording"])
        check("frozen command ids", ScreenRecordingAddon.commands.map(\.id)
              == ["command:nc-record-area", "command:nc-record-window", "command:nc-record-screen"])
        check("the switch needs Screen Recording", ScreenRecordingAddon.switches[0].requiredGrants == [.screenRecording])
        check("off by default", rig.controller.enabledCommands.isEmpty && rig.module == nil)
        await rig.toggle(true)
        check("on, its three commands are live", rig.controller.enabledCommands.count == 3 && rig.module != nil)
    }

    /// #937 acceptance 1 without capture: a window for 10 s with audio, 2 s off each end, saved as 6 s.
    static func recordTrimSave(_ rig: Rig) async {
        rig.run("record-window")
        check("Record Window opens the window picker", fake.selects == [.window])
        rig.run("record-area")
        rig.run("record-screen")
        check("commands while picking open nothing more", fake.selects == [.window] && fake.starts.isEmpty)
        fake.pick?(.window(42))
        await rig.settle()
        check("the picked window is recorded", fake.starts.map(\.target) == [.window(42)])
        check("with system audio and no microphone by default",
              fake.starts.first.map { $0.options.systemAudio && !$0.options.microphone } == true)
        check("into a MOV in the work folder",
              isIn(fake.starts.first?.file, try? workFolders.current()) && fake.starts.first?.file.pathExtension == "mov")
        check("the island shows the stop control at 0:00",
              rig.presenter.status?.symbol == "stop.circle" && rig.presenter.status?.text == "0:00"
                && rig.presenter.status?.label == "Stop Recording")
        check("the pill menu offers Stop Recording", rig.presenter.rows.map(\.title) == ["Stop Recording"])
        check("the Mac is kept awake while it records", fake.awake == 1)
        rig.clock.now = firstDate.addingTimeInterval(10)
        fake.tick?()
        check("the clock ticks to 0:10", rig.presenter.status?.text == "0:10")
        rig.presenter.statusTap?()
        check("the stop control leaves the island at once", rig.presenter.status == nil && rig.presenter.rows.isEmpty
              && fake.tick == nil && fake.awake == 0)
        await rig.settle()
        check("and stops the capture", fake.capture.stops == 1)
        let clip = fake.starts[0].file
        check("the trimmer opens on the clip with its duration",
              fake.trimmers.count == 1 && fake.trimmers[0].clip == clip && fake.trimmers[0].duration == 10)
        rig.run("record-screen")
        check("a Record command while trimming starts nothing", fake.starts.count == 1 && fake.selects.count == 1)
        var trim = RecordingTrim(duration: 10)
        trim.setStart(2)
        trim.setEnd(8)
        fake.answer?(.save(trim))
        await rig.settle()
        let export = files.withLock { $0.exports.last }
        let saved = desktopFolder.appending(path: fileName("mov"))
        check("Save passes the clip through, cut to 2–8 s",
              export?.source == clip && export?.plan == .passthrough && export?.trim.start == 2
                && export?.trim.end == 8 && export?.trim.length == 6)
        check("into the Desktop under macOS's name", export?.to == saved && exists(saved))
        check("the recorded clip is gone", !exists(clip))
        check("a result notice says it was saved", rig.presenter.last?.text == "Recording Saved"
              && rig.presenter.last?.isFailure == false)
        rig.presenter.taps["Recording Saved"]?()
        check("its tap shows the file in Finder", fake.revealed == [saved])
        rig.clock.now = firstDate
    }

    static func copyAndDiscard(_ rig: Rig) async {
        rig.defaults.set(RecordingOptions.Container.mp4.rawValue, forKey: RecordingOptions.Keys.container)
        rig.defaults.set(chosen.path(percentEncoded: false), forKey: RecordingOptions.Keys.folder)
        files.withLock { $0.passthrough = false }
        await record(rig, .area(CGRect(x: 10, y: 10, width: 200, height: 100)))
        check("the area is recorded, its master a MOV whatever the format",
              fake.starts.last?.target == .area(CGRect(x: 10, y: 10, width: 200, height: 100))
                && fake.starts.last?.file.pathExtension == "mov")
        var trim = RecordingTrim(duration: 10)
        trim.setEnd(5)
        fake.answer?(.copy(trim))
        await rig.settle()
        let export = files.withLock { $0.exports.last }
        check("Copy re-encodes when passthrough cannot", export?.plan == .reencode && export?.trim.end == 5)
        check("Copy writes into the work folder, never the chosen one",
              isIn(export?.to, try? workFolders.current()) && names(in: chosen).isEmpty)
        check("the copied file is on the clipboard", fake.clipboard.last == export?.to)
        check("a result notice says it was copied", rig.presenter.last?.text == "Recording Copied")

        await record(rig, .window(7))
        let clip = fake.starts.last!.file
        let count = files.withLock { $0.exports.count }
        fake.answer?(.discard)
        await rig.settle()
        check("Discard deletes the clip and exports nothing", !exists(clip) && files.withLock { $0.exports.count } == count)

        await record(rig, .window(7))
        fake.answer?(.save(RecordingTrim(duration: 10)))
        await rig.settle()
        let whole = files.withLock { $0.exports.last }
        check("an untrimmed MP4 is written whole from the MOV master, never renamed",
              whole?.plan == .reencode && whole?.trim.isWhole == true)
        check("into the chosen folder", whole?.to == chosen.appending(path: fileName("mp4")))

        await record(rig, .window(7))
        fake.answer?(.save(RecordingTrim(duration: 10)))
        await rig.settle()
        check("a taken name counts up", files.withLock { $0.exports.last?.to.lastPathComponent }
              == fileName("mp4", collision: 1))

        fake.clipboardWorks = false
        await record(rig, .window(7))
        fake.answer?(.copy(RecordingTrim(duration: 10)))
        await rig.settle()
        let uncopied = "Could not copy, so the recording is on the Desktop."
        check("a refused clipboard is a failure", rig.presenter.last?.text == uncopied
              && rig.presenter.last?.isFailure == true)
        rig.presenter.taps[uncopied]?()
        check("that leaves the export on the Desktop, and the notice's tap shows it",
              isIn(fake.revealed.last, desktopFolder) && fake.revealed.last.map(exists) == true
                && fake.revealed.last?.pathExtension == "mp4")
        fake.clipboardWorks = true

        files.withLock { $0.exportFails = true }
        await record(rig, .window(7))
        let kept = fake.starts.last!.file
        fake.answer?(.save(RecordingTrim(duration: 10)))
        await rig.settle()
        let rescued = "Export failed, so the whole recording is on the Desktop."
        check("a failed export is a failure", rig.presenter.last?.text == rescued && rig.presenter.last?.isFailure == true)
        check("that leaves nothing in the work folder or the folder that failed",
              !exists(kept) && names(in: chosen).count == 2)
        rig.presenter.taps[rescued]?()
        check("the clip is whole on the Desktop, and the notice's tap shows it",
              fake.revealed.last?.pathExtension == "mov" && isIn(fake.revealed.last, desktopFolder)
                && fake.revealed.last.map(exists) == true)
        files.withLock { $0.exportFails = false; $0.passthrough = true }

        try? FileManager.default.removeItem(at: chosen)
        await record(rig, .window(7))
        fake.answer?(.save(RecordingTrim(duration: 10)))
        await rig.settle()
        check("a recording folder that was deleted is made again",
              rig.presenter.last?.text == "Recording Saved" && names(in: chosen).count == 1)
        rig.defaults.removeObject(forKey: RecordingOptions.Keys.container)
        rig.defaults.removeObject(forKey: RecordingOptions.Keys.folder)
    }

    static func screenAndToggle(_ rig: Rig) async {
        let selects = fake.selects.count
        rig.run("record-screen")
        await rig.settle()
        check("Record Screen records the display under the pointer, no picker",
              fake.starts.last?.target == .display(3) && fake.selects.count == selects)
        rig.run("record-area")
        await rig.settle()
        check("any Record command stops the recording", fake.capture.stops == 1)
        fake.answer?(.discard)
        await rig.settle()

        let starts = fake.starts.count
        rig.run("record-window")
        fake.pick?(nil)
        await rig.settle()
        check("a cancelled pick records nothing", fake.starts.count == starts)
        rig.run("record-window")
        check("and the next command picks again", fake.selects.count == selects + 2)
        fake.pick?(nil)

        rig.run("record-screen")
        await rig.settle()
        rig.presenter.rowSelect?("stop")
        await rig.settle()
        check("the pill menu row stops it too", fake.capture.stops == 1)
        fake.answer?(.discard)
        await rig.settle()
    }

    static func refusals(_ rig: Rig) async {
        let (starts, selects) = (fake.starts.count, fake.selects.count)
        fake.screenGranted = false
        rig.run("record-area")
        check("without Screen Recording access nothing opens", fake.selects.count == selects && fake.starts.count == starts)
        check("and the island says why", rig.presenter.last?.text == "Screen Recording access is required."
              && rig.presenter.last?.isFailure == true)
        fake.screenGranted = true

        fake.display = nil
        rig.run("record-screen")
        check("no display under the pointer is a failure", rig.presenter.last?.text == "Nothing to record there.")
        fake.display = 3

        rig.defaults.set(true, forKey: RecordingOptions.Keys.microphone)
        fake.micGranted = false
        rig.run("record-screen")
        await rig.settle()
        check("a refused microphone records nothing", fake.starts.count == starts
              && rig.presenter.last?.text == "Microphone access is required.")
        fake.micGranted = true
        rig.run("record-screen")
        await rig.settle()
        check("a granted microphone is recorded", fake.starts.last?.options.microphone == true)
        rig.run("record-screen")
        await rig.settle()
        fake.answer?(.discard)
        await rig.settle()
        rig.defaults.removeObject(forKey: RecordingOptions.Keys.microphone)

        files.withLock { $0.freeBytes = RecordingDisk.minimumFreeBytesToStart - 1 }
        let before = fake.starts.count
        rig.run("record-screen")
        await rig.settle()
        check("a nearly full disk records nothing", fake.starts.count == before
              && rig.presenter.last?.text == "Not enough disk space to record.")
        files.withLock { $0.freeBytes = .max }
    }

    static func endings(_ rig: Rig) async {
        rig.run("record-screen")
        await rig.settle()
        let trimmers = fake.trimmers.count
        fake.ended?(RecordingTarget.Failure.captureFailed)
        check("a capture that ends by itself leaves the island", rig.presenter.status == nil)
        await rig.settle()
        check("and still opens the trimmer", fake.trimmers.count == trimmers + 1)
        fake.answer?(.discard)
        await rig.settle()

        rig.run("record-screen")
        await rig.settle()
        files.withLock { $0.freeBytes = RecordingDisk.minimumFreeBytesToContinue - 1 }
        fake.tick?()
        await rig.settle()
        check("a disk filling up stops the recording and says so", fake.capture.stops == 1
              && rig.presenter.status == nil
              && rig.presenter.posts.contains { $0.text == "Recording stopped: the disk is almost full." })
        check("and keeps what it recorded for the trimmer", fake.trimmers.count == trimmers + 2)
        files.withLock { $0.freeBytes = .max }
        fake.answer?(.discard)
        await rig.settle()

        fake.recordedSeconds = 0
        rig.run("record-screen")
        await rig.settle()
        let empty = fake.starts.last!.file
        rig.run("record-screen")
        await rig.settle()
        check("an empty recording opens no trimmer", fake.trimmers.count == trimmers + 2)
        check("and says so", rig.presenter.last?.text == "The recording is empty." && rig.presenter.last?.isFailure == true)
        check("and leaves no file", !exists(empty))
        fake.recordedSeconds = 10

        rig.run("record-screen")
        await rig.settle()
        fake.capture.stopFails = true
        rig.run("record-screen")
        await rig.settle()
        check("a stop that throws still keeps a clip with frames", fake.trimmers.count == trimmers + 3)
        fake.answer?(.discard)
        await rig.settle()

        fake.endsWhileStarting = true
        rig.run("record-screen")
        await rig.settle()
        await rig.settle()
        fake.endsWhileStarting = false
        check("a capture that ends while it starts is stopped, not left recording",
              fake.capture.stops == 1 && rig.presenter.status == nil && fake.trimmers.count == trimmers + 4)
        fake.answer?(.discard)
        await rig.settle()
    }

    static func switchOff(_ rig: Rig) async {
        rig.run("record-screen")
        await rig.settle()
        let recording = fake.starts.last!.file
        let capture = fake.capture
        var stopped = rig.module
        await rig.toggle(false)
        check("switching off leaves the island", rig.presenter.status == nil && rig.presenter.rows.isEmpty)
        await stopped?.settled()
        check("and stops the capture", capture.stops == 1)
        let saved = files.withLock { $0.exports.last }
        check("the clip is saved whole, untrimmed", saved?.source == recording && saved?.plan == .copy
              && isIn(saved?.to, desktopFolder) && !exists(recording))
        await rig.toggle(true)

        rig.run("record-screen")
        await rig.settle()
        rig.run("record-screen")
        await rig.settle()
        let trimming = fake.starts.last!.file
        let closes = fake.trimmerCloses
        stopped = rig.module
        await rig.toggle(false)
        check("switching off closes the trimmer", fake.trimmerCloses == closes + 1)
        await stopped?.settled()
        check("and saves the clip it showed", files.withLock { $0.exports.last?.source } == trimming)
        await rig.toggle(true)

        rig.run("record-area")
        let surfaces = fake.surfaceCloses
        let starts = fake.starts.count
        await rig.toggle(false)
        check("switching off closes the picker and records nothing",
              fake.surfaceCloses == surfaces + 1 && fake.starts.count == starts)
        await rig.toggle(true)
        rig.run("record-area")
        check("and the next command picks again", fake.pick != nil)
        fake.pick?(nil)
    }

    /// A quit while recording or trimming leaves the clip in that run's folder; the next start moves it out.
    static func recovery() async {
        func folder(_ name: String) -> URL {
            let url = work.appending(path: name, directoryHint: .isDirectory)
            precondition((try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)) != nil)
            return url
        }
        func clip(in folder: URL, seconds: TimeInterval) -> URL {
            let url = folder.appending(path: "\(UUID().uuidString).mov")
            writeClip(url, seconds: seconds)
            return url
        }
        let ended = folder("ended")
        let orphan = clip(in: ended, seconds: 10)
        let stub = ended.appending(path: "\(UUID().uuidString).mov")
        precondition((try? Data().write(to: stub)) != nil)
        let zero = clip(in: ended, seconds: 0)
        let unreadable = ended.appending(path: "\(UUID().uuidString).mov")
        precondition((try? Data("not a movie".utf8).write(to: unreadable)) != nil)
        // A folder another copy is still claiming is hidden until it is locked.
        let claiming = folder(".\(UUID().uuidString)")
        let claimed = clip(in: claiming, seconds: 10)
        let copied = ended.appending(path: "Copied.mov")
        writeClip(copied, seconds: 10)
        let quiet = folder("quiet")
        // A second holder of a folder under the same root is what another running copy of the app is.
        let otherCopy = RecordingWorkFolder(root: work)
        guard let theirs = try? otherCopy.current(), let ours = try? workFolders.current() else {
            return check("both running copies hold a work folder", false)
        }
        let live = clip(in: theirs, seconds: 10)
        let own = clip(in: ours, seconds: 10)
        let before = names(in: desktopFolder)
        let rig = Rig()
        check("off, the add-on still recovers", rig.module == nil)
        let recovery = rig.controller.context(forSwitch: "recording")?.recovery(ScreenRecordingRecovery.self)
        await recovery?.settled()
        let moved = names(in: desktopFolder).filter { !before.contains($0) }
        check("a clip left by a run that ended moves to the recording folder", !exists(orphan) && moved.count == 2
              && moved.allSatisfy { $0.hasSuffix(".mov") })
        check("a clip whose length cannot be read is recovered, not deleted", !exists(unreadable))
        check("a hidden folder is never taken for an ended run's", exists(claimed))
        check("a clip another running copy is still writing stays where it is", exists(live))
        check("and so does this run's own", exists(own))
        check("a stub that is not a movie yet is deleted, not recovered", !exists(stub))
        check("a clip whose length reads 0 is deleted, not recovered", !exists(zero))
        check("a copied export stays, and its folder with it", exists(copied))
        check("an ended run's empty folder is removed", !exists(quiet))
        let notice = "Recovered a recording from the last session."
        check("one notice says so", rig.presenter.posts.map(\.text) == [notice])
        rig.presenter.taps[notice]?()
        check("and its tap shows the file", moved.contains(fake.revealed.last?.lastPathComponent ?? ""))
        rig.finish()

        let again = Rig()
        await again.controller.context(forSwitch: "recording")?.recovery(ScreenRecordingRecovery.self)?.settled()
        check("with nothing left behind a start says nothing", again.presenter.posts.isEmpty)
        again.finish()
    }

    /// Records `target` up to the trimmer: pick it, start, stop with the island's control.
    static func record(_ rig: Rig, _ target: RecordingTarget) async {
        let slug = switch target {
        case .area: "record-area"
        default: "record-window"
        }
        rig.run(slug)
        fake.pick?(target)
        await rig.settle()
        rig.presenter.statusTap?()
        await rig.settle()
    }
}
