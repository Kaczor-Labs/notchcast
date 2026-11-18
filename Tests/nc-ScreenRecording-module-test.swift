// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Notchcast/ScreenRecording/ScreenRecordingAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/ScreenRecording/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/ScreenRecording/Service/RecordingSystem.swift
// notchcast-sources: Tinycast/Features/Notchcast/ScreenRecording/Service/ScreenRecordingModule.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift

import Foundation
import Synchronization
import SwiftUI

// The shipped `live` system and settings UI are left out: these stand in, so `makeModule` runs as shipped.

struct ScreenRecordingSettingsView: View {
    init(defaults: UserDefaults) {}
    var body: some View { EmptyView() }
}

let scratch = FileManager.default.temporaryDirectory.appending(path: "nc-ScreenRecording-module-test.\(UUID())")
let desktop = scratch.appending(path: "Desktop")
let work = scratch.appending(path: "Work")
let chosen = scratch.appending(path: "Chosen")
let firstDate = Date(timeIntervalSince1970: 1_763_290_800)

/// The module names files in this Mac's time zone, as shipped.
func fileName(_ ext: String, collision: Int = 0) -> String {
    RecordingFileName.name(date: firstDate, timeZone: .current, fileExtension: ext, collision: collision)
}

/// What the file-side fakes see and do, off the main actor.
struct FileSide: Sendable {
    var passthrough = true
    var exportFails = false
    var exports: [(source: URL, trim: RecordingTrim, plan: RecordingExport, to: URL)] = []
}

let files = Mutex(FileSide())

/// A clip's duration is written in it, so the nonisolated `duration` fake reads it from the file.
func writeClip(_ url: URL, seconds: TimeInterval) {
    precondition((try? Data(String(seconds).utf8).write(to: url)) != nil, "the fake clip is written")
}

@MainActor
final class FakeCapture: RecordingCapture {
    var stops = 0
    var stopFails = false

    func stop() async throws {
        stops += 1
        if stopFails { throw RecordingTarget.Failure.captureFailed }
    }
}

@MainActor
final class RecordingFake {
    var screenGranted = true
    var micGranted = true
    var display: UInt32? = 3
    var selects: [RecordingKind] = []
    var pick: (@MainActor (RecordingTarget?) -> Void)?
    var surfaceCloses = 0
    var starts: [(target: RecordingTarget, options: RecordingOptions, file: URL)] = []
    var ended: (@MainActor (any Error) -> Void)?
    var capture = FakeCapture()
    var recordedSeconds: TimeInterval = 10
    var tick: (@MainActor () -> Void)?
    var trimmers: [(clip: URL, duration: TimeInterval)] = []
    var answer: (@MainActor (RecordingTrimmerAnswer) -> Void)?
    var trimmerCloses = 0
    var clipboardWorks = true
    var clipboard: [URL] = []
    var revealed: [URL] = []
}

@MainActor let fake = RecordingFake()

extension RecordingSystem {
    static let live = RecordingSystem(
        grantScreen: { fake.screenGranted },
        grantMicrophone: { fake.micGranted },
        displayUnderCursor: { fake.display },
        select: { kind, completion in
            fake.selects.append(kind)
            fake.pick = completion
            return {
                fake.surfaceCloses += 1
                let pick = fake.pick
                fake.pick = nil
                pick?(nil)
            }
        },
        start: { target, options, file, ended in
            fake.starts.append((target, options, file))
            fake.ended = ended
            writeClip(file, seconds: fake.recordedSeconds)
            fake.capture = FakeCapture()
            return fake.capture
        },
        everySecond: { tick in
            fake.tick = tick
            return { fake.tick = nil }
        },
        workFolder: { work },
        desktop: { desktop },
        duration: { url in
            Double(String(bytes: try Data(contentsOf: url), encoding: .utf8) ?? "") ?? 0
        },
        passthroughWorks: { _, _ in files.withLock { $0.passthrough } },
        export: { source, trim, plan, destination in
            if files.withLock({ $0.exportFails }) { throw CocoaError(.fileWriteUnknown) }
            files.withLock { $0.exports.append((source, trim, plan, destination)) }
            try Data("exported".utf8).write(to: destination, options: .withoutOverwriting)
        },
        trim: { clip, duration, answer in
            fake.trimmers.append((clip, duration))
            fake.answer = answer
            return {
                fake.trimmerCloses += 1
                fake.answer = nil
            }
        },
        writeClipboard: { url in
            guard fake.clipboardWorks else { return false }
            fake.clipboard.append(url)
            return true
        },
        reveal: { fake.revealed.append($0) }
    )
}

@MainActor
final class FakePresenter: IslandPresenting {
    var posts: [IslandNotice] = []
    var taps: [String: @MainActor () -> Void] = [:]
    var status: IslandStatus?
    var statusTap: (@MainActor () -> Void)?
    var rows: [IslandMenuRow] = []
    var rowSelect: (@MainActor (String) -> Void)?

    func showLevel(_ level: IslandLevel) {}
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) {
        posts.append(notice)
        taps[notice.text] = onTap
    }
    func end(notice id: String) {}
    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {
        precondition(id == "recording" && (status == nil || status?.id == id), "one status, the add-on's own")
        self.status = status
        statusTap = onTap
    }
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {
        self.rows = rows
        rowSelect = onSelect
    }

    var last: IslandNotice? { posts.last }
}

@MainActor
final class TestClock {
    var now = firstDate
}

@MainActor
final class Rig {
    let suite = "nc-ScreenRecording-test.\(UUID())"
    let defaults: UserDefaults
    let presenter = FakePresenter()
    let clock = TestClock()
    let controller: NotchcastController

    init() {
        defaults = UserDefaults(suiteName: suite)!
        let hub = NotchcastTapHub(syntheticTag: 0x54494E59, isTrusted: { true }, makeSession: { _ in
            fatalError("Screen Recording declares no tap")
        })
        controller = NotchcastController(
            addons: [ScreenRecordingAddon.self], defaults: defaults, hub: hub, dictation: FakeDictation(),
            presenter: presenter, now: { [clock] in clock.now })
        controller.start()
    }

    /// The controller reconciles on its next main-actor turn; a few yields reach it, no clock involved.
    func toggle(_ on: Bool) async {
        controller.preferences.set("recording", on: on)
        for _ in 0..<20 where (module != nil) != on { await Task.yield() }
        precondition((module != nil) == on, "the switch reached the module")
    }

    var module: ScreenRecordingModule? {
        controller.context(forSwitch: "recording")?.module(ScreenRecordingModule.self)
    }

    func run(_ slug: String) {
        precondition(controller.run(entryID: "command:nc-\(slug)"), "\(slug) resolves")
    }

    func settle() async { await module?.settled() }

    func finish() {
        controller.stop()
        UserDefaults().removePersistentDomain(forName: suite)
    }
}

func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) }

func names(in folder: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []).sorted()
}

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
        for folder in [desktop, work, chosen] {
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
              fake.starts.first.map { $0.file.deletingLastPathComponent() == work && $0.file.pathExtension == "mov" } == true)
        check("the island shows the stop control at 0:00",
              rig.presenter.status?.symbol == "stop.circle" && rig.presenter.status?.text == "0:00"
                && rig.presenter.status?.label == "Stop Recording")
        check("the pill menu offers Stop Recording", rig.presenter.rows.map(\.title) == ["Stop Recording"])
        rig.clock.now = firstDate.addingTimeInterval(10)
        fake.tick?()
        check("the clock ticks to 0:10", rig.presenter.status?.text == "0:10")
        rig.presenter.statusTap?()
        check("the stop control leaves the island at once", rig.presenter.status == nil && rig.presenter.rows.isEmpty
              && fake.tick == nil)
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
        let saved = desktop.appending(path: fileName("mov"))
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
        check("the area is recorded as an MP4", fake.starts.last?.target == .area(CGRect(x: 10, y: 10, width: 200, height: 100))
              && fake.starts.last?.file.pathExtension == "mp4")
        var trim = RecordingTrim(duration: 10)
        trim.setEnd(5)
        fake.answer?(.copy(trim))
        await rig.settle()
        let export = files.withLock { $0.exports.last }
        check("Copy re-encodes when passthrough cannot", export?.plan == .reencode && export?.trim.end == 5)
        check("Copy writes into the work folder, never the chosen one",
              export?.to.deletingLastPathComponent() == work && names(in: chosen).isEmpty)
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
        check("an untrimmed save keeps the file as recorded", whole?.plan == .copy)
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
        check("a refused clipboard is a failure", rig.presenter.last?.text == "Could not copy to clipboard."
              && rig.presenter.last?.isFailure == true)
        fake.clipboardWorks = true

        files.withLock { $0.exportFails = true }
        await record(rig, .window(7))
        let kept = fake.starts.last!.file
        fake.answer?(.save(RecordingTrim(duration: 10)))
        await rig.settle()
        check("a failed export is a failure", rig.presenter.last?.text == "Could not save the recording."
              && rig.presenter.last?.isFailure == true)
        check("and keeps the recorded clip", exists(kept))
        files.withLock { $0.exportFails = false; $0.passthrough = true }
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

        fake.recordedSeconds = 0
        rig.run("record-screen")
        await rig.settle()
        let empty = fake.starts.last!.file
        rig.run("record-screen")
        await rig.settle()
        check("an empty recording opens no trimmer", fake.trimmers.count == trimmers + 1)
        check("and says so", rig.presenter.last?.text == "The recording is empty." && rig.presenter.last?.isFailure == true)
        check("and leaves no file", !exists(empty))
        fake.recordedSeconds = 10

        rig.run("record-screen")
        await rig.settle()
        fake.capture.stopFails = true
        rig.run("record-screen")
        await rig.settle()
        check("a stop that throws still keeps a clip with frames", fake.trimmers.count == trimmers + 2)
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
              && saved?.to.deletingLastPathComponent() == desktop && !exists(recording))
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
