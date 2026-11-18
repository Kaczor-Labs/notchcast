// notchcast-sources: Tinycast/Features/Notchcast/ScreenRecording/Model/*.swift

import CoreGraphics
import Foundation

/// #937 acceptance 2: recording state and trim range logic, with no capture, clock or window.
@main
enum ScreenRecordingModelTests {
    static var failures = 0
    static var checks = 0

    static func check(_ name: String, _ value: Bool) {
        checks += 1
        if !value { failures += 1; print("FAIL \(name)") }
    }

    static func main() {
        state()
        clock()
        trim()
        geometry()
        options()
        print("\(checks) screen recording model checks; \(failures) failures")
        if failures > 0 { exit(1) }
        print("PASSED")
    }

    static func state() {
        let start = Date(timeIntervalSince1970: 1_000)
        var state = RecordingState()
        check("idle at first", state.phase == .idle && !state.isRecording)
        check("no clock while idle", state.elapsed(at: start) == nil)
        check("an area asks for a selection", state.command(.area) == .select(.area))
        check("a second command while selecting is ignored", state.command(.screen) == .ignore)
        check("a cancelled pick returns to idle", !state.selected(false) && state.phase == .idle)
        check("a window asks for a selection", state.command(.window) == .select(.window))
        check("a pick starts the capture", state.selected(true) && state.phase == .starting)
        check("commands wait while starting", state.command(.area) == .ignore)
        check("stop is refused before the capture runs", !state.stopRequested())
        check("the capture starts", state.started(at: start) && state.isRecording)
        check("started twice is refused", !state.started(at: start))
        check("elapsed counts from the start", state.elapsed(at: start.addingTimeInterval(10)) == 10)
        check("elapsed never runs backwards", state.elapsed(at: start.addingTimeInterval(-5)) == 0)
        check("any Record command stops a recording", state.command(.screen) == .stop && state.phase == .stopping)
        check("commands wait while stopping", state.command(.window) == .ignore)
        check("finished opens the trimmer", state.finished() && state.phase == .trimming)
        check("commands wait while trimming", state.command(.area) == .ignore)
        state.reset()
        check("the screen starts without a selection", state.command(.screen) == .startScreen)
        check("a pick outside selecting is ignored", !state.selected(true) && state.phase == .starting)
        check("finished outside stopping is refused", !state.finished())
        _ = state.started(at: start)
        check("the stop control stops", state.stopRequested() && state.phase == .stopping)
        check("a second stop is refused", !state.stopRequested())
    }

    static func clock() {
        let cases: [(TimeInterval, String)] = [
            (0, "0:00"), (9.9, "0:09"), (61, "1:01"), (599, "9:59"), (600, "10m"), (5999, "99m"),
            (6000, "1h40"), (35999, "9h59"), (36000, "10h"), (-3, "0:00"), (.nan, "0:00"),
        ]
        for (seconds, text) in cases {
            check("\(seconds) s reads \(text), got \(RecordingClock.text(seconds))", RecordingClock.text(seconds) == text)
        }
        let longest = (0..<36000).map { RecordingClock.text(TimeInterval($0)).count }.max() ?? 0
        check("the island's four characters hold every clock under ten hours", longest <= 4)
    }

    static func trim() {
        var trim = RecordingTrim(duration: 10)
        check("a new trim keeps the whole clip", trim.start == 0 && trim.end == 10 && trim.isWhole)
        check("the whole clip is kept as recorded", RecordingExport.plan(trim, passthroughWorks: true) == .copy)
        trim.setStart(2)
        trim.setEnd(8)
        check("2 s off each end of 10 s leaves 6 s", trim.start == 2 && trim.end == 8 && trim.length == 6)
        check("a cut clip is no longer whole", !trim.isWhole)
        check("a cut passes through when it can", RecordingExport.plan(trim, passthroughWorks: true) == .passthrough)
        check("a cut re-encodes when it cannot", RecordingExport.plan(trim, passthroughWorks: false) == .reencode)
        trim.setStart(9)
        check("a start past the end pushes the end ahead of it",
              trim.start == 9 && abs(trim.end - (9 + RecordingTrim.minimumLength)) < 1e-9)
        trim.setEnd(0)
        check("an end before the start gives way to it",
              trim.start == 9 && abs(trim.end - (9 + RecordingTrim.minimumLength)) < 1e-9)
        trim.setStart(9.95)
        check("a start at the very end leaves the minimum before it",
              abs(trim.start - (10 - RecordingTrim.minimumLength)) < 1e-9 && abs(trim.end - 10) < 1e-9)
        trim.setStart(-4)
        trim.setEnd(50)
        check("handles stay inside the clip", trim.start == 0 && trim.end == 10)
        trim.setStart(3)
        trim.setEnd(7)
        trim.setStart(.nan)
        trim.setEnd(.infinity)
        check("non-finite times fall back to the clip's ends", trim.start == 0 && trim.end == 10 && trim.isWhole)
        let empty = RecordingTrim(duration: .nan)
        check("an unreadable duration is empty and whole", empty.duration == 0 && empty.length == 0 && empty.isWhole)
        var short = RecordingTrim(duration: 0.05)
        short.setStart(1)
        check("a clip shorter than the minimum keeps all of it", short.start == 0 && short.end == 0.05)

        let id = UUID()
        let destination = URL(filePath: "/tmp/clips/Screen Recording.mov")
        check("a cut is written beside its destination under a hidden name",
              RecordingExport.stagingURL(for: destination, id: id)
                == URL(filePath: "/tmp/clips/.notchcast-partial-\(id.uuidString).mov"))
    }

    static func geometry() {
        let windows = [
            RecordingWindow(id: 1, ownerPID: 7, frame: CGRect(x: 0, y: 0, width: 300, height: 200)),
            RecordingWindow(id: 2, ownerPID: 9, frame: CGRect(x: 0, y: 0, width: 300, height: 200), layer: 25),
            RecordingWindow(id: 3, ownerPID: 9, frame: CGRect(x: 0, y: 0, width: 300, height: 200), alpha: 0),
            RecordingWindow(id: 4, ownerPID: 9, frame: CGRect(x: 0, y: 0, width: 30, height: 200)),
            RecordingWindow(id: 5, ownerPID: 9, frame: CGRect(x: 50, y: 50, width: 100, height: 100)),
            RecordingWindow(id: 6, ownerPID: 9, frame: CGRect(x: 0, y: 0, width: 300, height: 200)),
        ]
        let pickable = RecordingGeometry.pickable(windows, ownPID: 7)
        check("only ordinary visible windows of other apps are pickable", pickable.map(\.id) == [5, 6])

        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        check("a click is not an area",
              RecordingGeometry.area(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 12, y: 13), in: bounds) == nil)
        check("a drag either way is the same area",
              RecordingGeometry.area(from: CGPoint(x: 110, y: 90), to: CGPoint(x: 10, y: 20), in: bounds)
                == CGRect(x: 10, y: 20, width: 100, height: 70))
        check("a drag past the display is cut to it",
              RecordingGeometry.area(from: CGPoint(x: 300, y: 200), to: CGPoint(x: 900, y: 900), in: bounds)
                == CGRect(x: 300, y: 200, width: 100, height: 100))
        let second = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        check("an area becomes its display's own source rect",
              RecordingGeometry.sourceRect(CGRect(x: 1540, y: 100, width: 200, height: 100), onDisplay: second)
                == CGRect(x: 100, y: 100, width: 200, height: 100))
        check("an area across two displays has no source rect",
              RecordingGeometry.sourceRect(CGRect(x: 1400, y: 100, width: 200, height: 100), onDisplay: second) == nil)
        let pixels = RecordingGeometry.pixelSize(points: CGSize(width: 100.3, height: 51.5), scale: 2)
        check("pixels round down to even sides", pixels?.width == 200 && pixels?.height == 102)
        let tiny = RecordingGeometry.pixelSize(points: CGSize(width: 5, height: 300), scale: 1)
        check("a side never drops below the minimum", tiny?.width == 32 && tiny?.height == 300)
        check("an empty capture has no size", RecordingGeometry.pixelSize(points: .zero, scale: 2) == nil)
        check("an oversize capture has no size",
              RecordingGeometry.pixelSize(points: CGSize(width: 9000, height: 10), scale: 2) == nil)
        check("a broken scale has no size",
              RecordingGeometry.pixelSize(points: CGSize(width: 10, height: 10), scale: .nan) == nil)
        check("an absurd size has no size, rather than a crash",
              RecordingGeometry.pixelSize(points: CGSize(width: 1e300, height: 10), scale: 2) == nil)
    }

    static func options() {
        let suite = "nc-ScreenRecording-model-test.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        check("defaults: system audio on, no microphone, H.264 in MOV on the Desktop",
              RecordingOptions(defaults) == RecordingOptions()
                && RecordingOptions().systemAudio && !RecordingOptions().microphone
                && RecordingOptions().codec == .h264 && RecordingOptions().container == .mov
                && RecordingOptions().folder == nil)
        typealias Keys = RecordingOptions.Keys
        defaults.set(false, forKey: Keys.systemAudio)
        defaults.set(true, forKey: Keys.microphone)
        defaults.set("hevc", forKey: Keys.codec)
        defaults.set("mp4", forKey: Keys.container)
        defaults.set("/tmp/clips", forKey: Keys.folder)
        let read = RecordingOptions(defaults)
        check("every stored choice is read back",
              !read.systemAudio && read.microphone && read.codec == .hevc && read.container == .mp4
                && read.folder == "/tmp/clips")
        defaults.set("av1", forKey: Keys.codec)
        defaults.set("mkv", forKey: Keys.container)
        check("unknown stored values fall back", RecordingOptions(defaults).codec == .h264
              && RecordingOptions(defaults).container == .mov)

        let date = Date(timeIntervalSince1970: 1_763_290_800)
        let utc = TimeZone(identifier: "UTC")!
        check("files take macOS's screen recording name",
              RecordingFileName.name(date: date, timeZone: utc, fileExtension: "mov")
                == "Screen Recording 2025-11-16 at 11.00.00.mov")
        check("a taken name counts up",
              RecordingFileName.name(date: date, timeZone: utc, fileExtension: "mp4", collision: 2)
                == "Screen Recording 2025-11-16 at 11.00.00 (2).mp4")
        check("failures read as plain sentences",
              RecordingTarget.failureMessage(RecordingTarget.Failure.screenPermission)
                == "Screen Recording access is required."
                && RecordingTarget.failureMessage(CocoaError(.fileWriteNoPermission))
                == "Could not save the recording.")
    }
}
