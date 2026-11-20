import AVFoundation
import Foundation
import Synchronization
import SwiftUI

// The shipped `live` system and settings UI are left out: these stand in, so `makeModule` runs as shipped.

struct ScreenRecordingSettingsView: View {
    init(defaults: UserDefaults) {}
    var body: some View { EmptyView() }
}

let scratch = FileManager.default.temporaryDirectory.appending(path: "nc-ScreenRecording-module-test.\(UUID())")
let desktopFolder = scratch.appending(path: "Desktop")
let work = scratch.appending(path: "Work")
let workFolders = RecordingWorkFolder(root: work)
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
    var freeBytes = Int64.max
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
    var awake = 0
    var endsWhileStarting = false
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
            if fake.endsWhileStarting { ended(RecordingTarget.Failure.captureFailed) }
            return fake.capture
        },
        everySecond: { tick in
            fake.tick = tick
            return { fake.tick = nil }
        },
        workFolder: { try workFolders.current() },
        abandonedWorkFolders: { workFolders.abandoned() },
        desktop: { desktopFolder },
        keepAwake: {
            fake.awake += 1
            return { fake.awake -= 1 }
        },
        freeBytes: { files.withLock { $0.freeBytes } },
        duration: { url in
            let data = try Data(contentsOf: url)
            // A real stub a quit left before the first fragment fails to parse as a movie.
            if data.isEmpty { throw AVError(.fileFailedToParse) }
            guard let seconds = Double(String(bytes: data, encoding: .utf8) ?? "") else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return seconds
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

/// A folder URL may or may not end in a slash, so folders are compared by their components.
func isIn(_ file: URL?, _ folder: URL?) -> Bool {
    file != nil && file?.deletingLastPathComponent().standardizedFileURL.pathComponents
        == folder?.standardizedFileURL.pathComponents
}

func names(in folder: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []).sorted()
}
