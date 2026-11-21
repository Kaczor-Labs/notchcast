// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Notchcast/Screenshots/ScreenshotsAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/Screenshots/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Screenshots/Service/ScreenshotSystem.swift
// notchcast-sources: Tinycast/Features/Notchcast/Screenshots/Service/ScreenshotsModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Screenshots/Service/ScrollingCaptureRun.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift

import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import Synchronization

// The shipped `live` and settings UI are left out: these stand in, so `makeModule` runs as shipped.

struct ScreenshotsSettingsView: View {
    init(defaults: UserDefaults) {}
    var body: some View { EmptyView() }
}

let scratch = FileManager.default.temporaryDirectory.appending(path: "nc-Screenshots-module-test.\(UUID())")
let downloadsFolder = scratch.appending(path: "Downloads")
let chosenFolder = scratch.appending(path: "Chosen")
let fixedDate = Date(timeIntervalSince1970: 1_763_290_800)

/// A scrolled page's viewport, `offset` rows down a document no two rows of which repeat nearby.
func page(offset: Int, seed: UInt32 = 0) -> CGImage {
    let width = 32, height = 120
    var pixels = [UInt8](repeating: 0, count: width * height)
    for row in 0..<height {
        for column in 0..<width {
            var value = UInt32((row + offset) * width + column) &+ seed
            value = (value ^ (value >> 16)) &* 0x45d9f3b
            pixels[row * width + column] = UInt8(truncatingIfNeeded: value ^ (value >> 13))
        }
    }
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                   space: CGColorSpaceCreateDeviceGray(),
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                   provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil, shouldInterpolate: false,
                   intent: .defaultIntent)!
}

/// The run's uptime in whole microseconds, moved only by its own pauses and frames, so a wait always ends.
final class FakeClock: Sendable {
    private let micros = Mutex(0)

    var now: TimeInterval { Double(micros.withLock { $0 }) / 1_000_000 }

    func advance(_ by: TimeInterval) { micros.withLock { $0 += max(1, Int((by * 1_000_000).rounded(.up))) } }
}

let clock = FakeClock()

func image(width: Int, height: Int) -> CGImage {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return context.makeImage()!
}

@MainActor
final class ScreenshotFake {
    var granted = true
    var holdFreeze = false
    var freezeGate: CheckedContinuation<Void, Never>?
    var freezes: [(point: CGPoint?, exclusion: ScreenshotExclusion)] = []
    var displays = [
        ScreenshotFrozenDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 50),
                                image: image(width: 200, height: 100)),
        ScreenshotFrozenDisplay(id: 2, frame: CGRect(x: 100, y: 0, width: 100, height: 50),
                                image: image(width: 100, height: 50)),
    ]
    var windows: [ScreenshotWindow] = []
    var cursor = CGPoint(x: 150, y: 10)
    var frozenWindows: [[UInt32]] = []
    var windowWidth = 30
    var closedWindows: Set<UInt32> = []
    var clipboardWorks = true
    var clipboard: [Data] = []
    var surfaces: [(displays: [UInt32], windows: [UInt32])] = []
    var answer: (@MainActor (ScreenshotRequest?) -> Void)?
    var closes = 0
    var lines: [ScreenTextLine] = []
    var recognizedWidths: [Int] = []
    var textWorks = true
    var texts: [String] = []
    var settingsOpened = 0
    var holdRecognize = false
    var recognizeFails = false
    var recognizeGate: CheckedContinuation<Void, Never>?
    var holdWarm = false
    var warmGate: CheckedContinuation<Void, Never>?
    var warmOffMain: [Bool] = []
    var warmCancelled: [Bool] = []
    var frames: [CGImage?] = []
    var served = 0
    var holdFrames = true
    var frameSeconds = 0.01
    var frameGate: CheckedContinuation<Void, Never>?
    var regions: [ScrollingCaptureRegion] = []
    var regionFails = false
    var guides = 0
    var hiddenGuides = 0
    var edited: [CGImage] = []

    /// Once `frames` are served it waits for the test, so the run stands still while it is checked.
    func frame() async -> CGImage? {
        if served >= frames.count, holdFrames { await withCheckedContinuation { frameGate = $0 } }
        defer { served += 1 }
        clock.advance(frameSeconds)
        return frames.isEmpty ? nil : frames[min(served, frames.count - 1)]
    }

    func releaseFrames(holding: Bool = false) {
        holdFrames = holding
        let gate = frameGate
        frameGate = nil
        gate?.resume()
    }

    func scroll(_ frames: [CGImage?]) {
        self.frames = frames
        served = 0
        holdFrames = true
    }

    struct VisionFailed: Error {}

    func recognize(_ image: CGImage) async throws -> [ScreenTextLine] {
        recognizedWidths.append(image.width)
        if holdRecognize { await withCheckedContinuation { recognizeGate = $0 } }
        if recognizeFails { throw VisionFailed() }
        return lines
    }

    func warm(offMain: Bool) async {
        warmOffMain.append(offMain)
        if holdWarm { await withCheckedContinuation { warmGate = $0 } }
    }

    func releaseWarm() {
        warmGate?.resume()
        warmGate = nil
    }

    func releaseRecognize() {
        recognizeGate?.resume()
        recognizeGate = nil
    }

    func release() {
        freezeGate?.resume()
        freezeGate = nil
    }

    func pick(_ request: ScreenshotRequest?) {
        let answer = answer
        self.answer = nil
        answer?(request)
    }
}

@MainActor let fake = ScreenshotFake()

extension ScreenshotSystem {
    static let live = ScreenshotSystem(
        grantAccess: { fake.granted },
        freeze: { point, exclusion in
            fake.freezes.append((point, exclusion))
            if fake.holdFreeze { await withCheckedContinuation { fake.freezeGate = $0 } }
            return fake.displays.filter { display in point.map(display.frame.contains) ?? true }
        },
        windows: { fake.windows },
        freezeWindows: { ids in
            fake.frozenWindows.append(ids)
            return Dictionary(uniqueKeysWithValues: ids.filter { !fake.closedWindows.contains($0) }
                .map { ($0, image(width: fake.windowWidth, height: 20)) })
        },
        cursor: { fake.cursor },
        writeClipboard: { data in
            guard fake.clipboardWorks else { return false }
            fake.clipboard.append(data)
            return true
        },
        writeText: { text in
            guard fake.textWorks else { return false }
            fake.texts.append(text)
            return true
        },
        recognizeText: { image in try await fake.recognize(image) },
        warmTextRecognition: {
            let offMain = pthread_main_np() == 0
            await fake.warm(offMain: offMain)
            let cancelled = Task.isCancelled
            await MainActor.run { fake.warmCancelled.append(cancelled) }
        },
        openScreenRecordingSettings: { fake.settingsOpened += 1 },
        downloads: { downloadsFolder },
        chooseSaveFile: { _ in nil },
        select: { frozen, windows, completion in
            fake.surfaces.append((frozen.map(\.id), windows.map(\.id)))
            fake.answer = completion
            return {
                fake.closes += 1
                fake.pick(nil)
            }
        },
        edit: { image, _, _ in
            fake.edited.append(image)
            return {}
        },
        openRegion: { region in
            fake.regions.append(region)
            if fake.regionFails { throw ScreenshotRequest.Failure.targetUnavailable }
            return ScreenshotRegionSource { await fake.frame() }
        },
        uptime: { clock.now },
        pause: { seconds in
            clock.advance(seconds)
            await Task.yield()
        },
        showGuide: { _ in
            fake.guides += 1
            return { fake.hiddenGuides += 1 }
        }
    )
}

@MainActor
final class FakePresenter: IslandPresenting {
    var posts: [IslandNotice] = []
    var events: [String] = []

    func showLevel(_ level: IslandLevel) {}
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) {
        posts.append(notice)
        events.append("post " + notice.id)
    }
    func end(notice id: String) { events.append("end " + id) }
    var status: IslandStatus?
    var statusTap: (@MainActor () -> Void)?
    var rows: [IslandMenuRow] = []
    var select: (@MainActor (String) -> Void)?
    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {
        precondition(status == nil || status?.id == id, "a status is set under its own id")
        self.status = status
        statusTap = onTap
    }
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {
        precondition(owner == "screenshot.scrolling", "only the scrolling capture has menu rows")
        self.rows = rows
        select = onSelect
    }
}

@MainActor
final class Rig {
    let suite = "nc-Screenshots-test.\(UUID())"
    let defaults: UserDefaults
    let presenter = FakePresenter()
    let controller: NotchcastController

    init() {
        defaults = UserDefaults(suiteName: suite)!
        let hub = NotchcastTapHub(syntheticTag: 0x54494E59, isTrusted: { true }, makeSession: { _ in
            fatalError("Screenshots declares no tap")
        })
        controller = NotchcastController(
            addons: [ScreenshotsAddon.self], defaults: defaults, hub: hub, dictation: FakeDictation(),
            presenter: presenter, now: { fixedDate })
        controller.start()
    }

    func fire(_ id: String) {
        precondition(controller.run(entryID: id), "\(id) resolves")
    }

    func finish() {
        controller.stop()
        UserDefaults().removePersistentDomain(forName: suite)
    }
}

let area = "command:nc-screenshot-area"
let display = "command:nc-screenshot-display"
let editLast = "command:nc-edit-last-screenshot"
let text = "command:nc-capture-text"
let scroll = "command:nc-scrolling-capture"

func drain() async { try? await Task.sleep(for: .milliseconds(120)) }

/// Yields the main actor until the condition holds; no clock, so a hang fails by the cap instead.
@MainActor
func settle(_ what: String, tries: Int = 100_000, until condition: @MainActor () -> Bool) async {
    for _ in 0..<tries {
        if condition() { return }
        await Task.yield()
    }
    preconditionFailure("never settled: \(what)")
}

let recognizing = IslandNotice(
    id: "screenshot.text", symbol: "text.viewfinder", text: "Recognizing text…", progress: IslandProgress(fraction: nil))

func files(in folder: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []).sorted()
}

func isPNG(_ data: Data?) -> Bool { data?.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]) }

func pngDPI(_ data: Data?) -> Double? {
    data.flatMap { CGImageSourceCreateWithData($0 as CFData, nil) }
        .flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }?[kCGImagePropertyDPIWidth] as? Double
}

func pngHeight(_ data: Data?) -> Int? {
    data.flatMap { CGImageSourceCreateWithData($0 as CFData, nil) }
        .flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }?.height
}

func pngWidth(_ data: Data?) -> Int? {
    data.flatMap { CGImageSourceCreateWithData($0 as CFData, nil) }
        .flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }?.width
}

@main
enum ScreenshotsModuleTests {
    @MainActor
    static func main() async {
        precondition((try? FileManager.default.createDirectory(at: downloadsFolder, withIntermediateDirectories: true)) != nil)
        precondition((try? FileManager.default.createDirectory(at: chosenFolder, withIntermediateDirectories: true)) != nil)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let rig = Rig()
        let presenter = rig.presenter

        precondition(ScreenshotsAddon.switches.map(\.id) == ["screenshot"], "v1 switch id")
        precondition(ScreenshotsAddon.commands.map(\.id) == [area, display, editLast, text, scroll],
                     "frozen command ids")
        precondition(ScreenshotsAddon.commands.map { "hotkey." + $0.id }
                     == ["hotkey.command:nc-screenshot-area", "hotkey.command:nc-screenshot-display",
                         "hotkey.command:nc-edit-last-screenshot", "hotkey.command:nc-capture-text",
                         "hotkey.command:nc-scrolling-capture"],
                     "each stored binding names its command")
        precondition(rig.controller.enabledCommands.map(\.id) == [area, display, editLast, text, scroll],
                     "on by default")
        await settle("the first warm-up", until: { fake.warmCancelled.count == 1 })
        precondition(fake.warmOffMain == [true] && fake.warmCancelled == [false],
                     "the module's start warms the recogniser once, off the main actor")

        fake.holdFreeze = true
        precondition(rig.controller.run(entryID: area), "the area binding resolves")
        await drain()
        precondition(fake.freezes.count == 1 && fake.freezes[0].point == nil, "area freezes every display")
        let exclusion = fake.freezes[0].exclusion
        precondition(exclusion.pid == ProcessInfo.processInfo.processIdentifier, "the exclusion knows our own windows")
        precondition(rig.controller.run(entryID: area) && rig.controller.run(entryID: display),
                     "a second trigger still resolves")
        await drain()
        precondition(fake.freezes.count == 1 && fake.surfaces.isEmpty, "a second trigger while active is ignored")

        let own = exclusion.pid
        fake.windows = [
            ScreenshotWindow(id: 50, ownerPID: own, frame: CGRect(x: 0, y: 0, width: 200, height: 50),
                             isShared: false),
            ScreenshotWindow(id: 51, ownerPID: 9, frame: CGRect(x: 10, y: 10, width: 60, height: 40)),
            ScreenshotWindow(id: 52, ownerPID: 9, frame: CGRect(x: 10, y: 10, width: 60, height: 40), layer: 25),
        ]
        fake.holdFreeze = false
        fake.release()
        await drain()
        precondition(fake.surfaces.count == 1, "one surface after the freeze")
        precondition(fake.surfaces[0].displays == [1, 2] && fake.surfaces[0].windows == [51],
                     "the surface gets every frozen display and only pickable windows")
        precondition(rig.controller.run(entryID: display))
        await drain()
        precondition(fake.freezes.count == 1, "still one session while the surface is up")
        fake.pick(.rect(CGRect(x: 10, y: 10, width: 20, height: 10)))
        await drain()
        precondition(fake.clipboard.count == 1 && isPNG(fake.clipboard.last), "clipboard by default")
        precondition(pngDPI(fake.clipboard.last).map { abs($0 - 144) < 1 } == true,
                     "an unedited Retina capture says 144 dpi, like an edited one")
        precondition(files(in: downloadsFolder).isEmpty && presenter.posts.isEmpty, "no file by default")

        precondition(rig.controller.run(entryID: area))
        await drain()
        precondition(fake.frozenWindows.last == [51], "only pickable windows are frozen, before selection")
        fake.windowWidth = 31
        fake.closedWindows = [51]
        fake.pick(.window(51))
        await drain()
        precondition(fake.clipboard.count == 2 && pngWidth(fake.clipboard.last) == 30,
                     "a click saves the frozen window, even after it changed or closed")
        precondition(pngDPI(fake.clipboard.last).map { abs($0 - 72) < 1 } != false,
                     "a window's scale is its own pixels per point, not its display's")
        fake.windowWidth = 30

        rig.fire(area)
        await drain()
        precondition(fake.surfaces.last?.windows == [], "a window that would not freeze is not offered")
        fake.pick(nil)
        await drain()
        fake.closedWindows = []

        rig.fire(area)
        await drain()
        fake.pick(nil)
        await drain()
        precondition(fake.clipboard.count == 2 && presenter.posts.isEmpty, "cancel writes nothing")

        rig.fire(area)
        await drain()
        fake.pick(.rect(CGRect(x: 10, y: 10, width: 0, height: 10)))
        await drain()
        precondition(presenter.posts.last?.text == "Capture area is unavailable."
                     && presenter.posts.last?.isFailure == true, "an empty rect is refused")
        rig.fire(area)
        await drain()
        fake.pick(.rect(CGRect(x: 90, y: 10, width: 20, height: 10)))
        await drain()
        precondition(presenter.posts.count == 2, "a rect across two displays is refused")

        rig.defaults.set("file", forKey: "notchcast.screenshot.destination")
        rig.fire(display)
        await drain()
        precondition(fake.freezes.last?.point == fake.cursor, "the screen capture freezes the display under the cursor")
        let first = ScreenshotFileName.name(date: fixedDate, timeZone: .current)
        precondition(files(in: downloadsFolder) == [first], "no folder set means Downloads, v1 name")
        precondition(fake.clipboard.count == 2, "file only leaves the clipboard alone")
        rig.defaults.set(chosenFolder.path(percentEncoded: false), forKey: "notchcast.screenshot.folder")
        rig.fire(display)
        await drain()
        rig.fire(display)
        await drain()
        precondition(files(in: chosenFolder) == [first, ScreenshotFileName.name(
            date: fixedDate, timeZone: .current, collision: 1)].sorted(), "chosen folder, v1 collision suffix")

        rig.defaults.set("both", forKey: "notchcast.screenshot.destination")
        fake.clipboardWorks = false
        let posts = presenter.posts.count
        rig.fire(display)
        await drain()
        precondition(files(in: chosenFolder).count == 3 && presenter.posts.count == posts,
                     "a failed clipboard with the file saved is no failure")
        rig.defaults.set("clipboard", forKey: "notchcast.screenshot.destination")
        rig.fire(display)
        await drain()
        precondition(presenter.posts.last?.text == "Could not copy to clipboard.", "clipboard only failure reports")
        fake.clipboardWorks = true

        rig.defaults.set("both", forKey: "notchcast.screenshot.destination")
        let saved = files(in: chosenFolder)
        let images = fake.clipboard.count
        fake.lines = [
            ScreenTextLine(text: "second", box: CGRect(x: 0.1, y: 0.48, width: 0.5, height: 0.1)),
            ScreenTextLine(text: "first", box: CGRect(x: 0.1, y: 0.6, width: 0.5, height: 0.1)),
        ]
        rig.fire(text)
        await drain()
        precondition(fake.freezes.last?.point == nil && fake.surfaces.count == 7, "text reuses the area surface")
        fake.pick(.rect(CGRect(x: 10, y: 10, width: 20, height: 10)))
        await drain()
        precondition(fake.recognizedWidths == [40] && fake.texts == ["first\nsecond"],
                     "the selected pixels' text is copied in reading order")
        precondition(presenter.posts.last?.text == "first" && presenter.posts.last?.isFailure == false,
                     "a notice shows the first line")
        precondition(presenter.posts.suffix(2).map(\.id) == ["screenshot.text", "screenshot.text"]
                     && presenter.posts.suffix(2).first == recognizing && presenter.posts.last?.progress == nil,
                     "the first line replaces the progress notice under its id")
        precondition(files(in: chosenFolder) == saved && fake.clipboard.count == images,
                     "the image is never saved or copied, whatever the screenshot destination")
        rig.defaults.set("clipboard", forKey: "notchcast.screenshot.destination")

        fake.lines = []
        rig.fire(text)
        await drain()
        fake.pick(.window(51))
        await drain()
        precondition(presenter.posts.last?.text == "No text found in the selected area."
                     && fake.texts.count == 1, "no text found leaves the clipboard alone")

        let notices = presenter.posts.count
        rig.fire(text)
        await drain()
        fake.pick(nil)
        await drain()
        precondition(fake.recognizedWidths.count == 2 && presenter.posts.count == notices, "Esc recognises nothing")

        fake.recognizeFails = true
        rig.fire(text)
        await drain()
        fake.pick(.window(51))
        await drain()
        precondition(presenter.posts.last?.text == "Could not read text from the selection."
                     && presenter.posts.last?.isFailure == true, "a recognition error is not a capture error")
        fake.recognizeFails = false

        fake.lines = [ScreenTextLine(text: "kept", box: CGRect(x: 0, y: 0.5, width: 1, height: 0.1))]
        fake.textWorks = false
        rig.fire(text)
        await drain()
        fake.pick(.display(1))
        await drain()
        precondition(presenter.posts.last?.text == "Could not copy to clipboard.", "a failed text copy reports")
        fake.textWorks = true

        fake.granted = false
        let freezes = fake.freezes.count
        rig.fire(area)
        await drain()
        precondition(presenter.posts.last?.text == "Screen Recording access is required." && fake.freezes.count == freezes,
                     "no access, no freeze")
        precondition(fake.settingsOpened == 0, "a screenshot leaves System Settings closed")
        rig.fire(text)
        await drain()
        precondition(presenter.posts.last?.text == "Screen Recording access is required."
                     && fake.freezes.count == freezes && fake.settingsOpened == 1,
                     "text without access opens the Screen Recording pane")
        fake.granted = true

        precondition(fake.warmOffMain.count == 1, "captures never warm again")
        rig.fire(area)
        await drain()
        let shots = fake.clipboard.count
        rig.controller.preferences.set("screenshot", on: false)
        await drain()
        precondition(fake.closes == 1 && fake.answer == nil, "switching off closes the surface")
        precondition(fake.clipboard.count == shots && !rig.controller.run(entryID: area), "and its commands go")

        rig.finish()
        await warmUpCases()
        await scrollingCases()
        print("nc-Screenshots-module-test: ok")
    }

    @MainActor
    static func warmUpCases() async {
        fake.holdWarm = true
        let rig = Rig()
        let presenter = rig.presenter
        await settle("a held warm-up", until: { fake.warmGate != nil })
        precondition(fake.warmOffMain == [true, true], "a new start warms")
        rig.controller.preferences.set("screenshot", on: false)
        await settle("the switch off", until: { presenter.events == ["end screenshot.text"] })
        fake.releaseWarm()
        await settle("the cancelled warm-up", until: { fake.warmCancelled.count == 2 })
        precondition(fake.warmCancelled.last == true, "switching off cancels a warm-up in flight")
        precondition(presenter.posts.isEmpty, "a warm-up shows nothing")

        rig.controller.preferences.set("screenshot", on: true)
        await settle("the warm-up after switching on", until: { fake.warmGate != nil })
        precondition(fake.warmOffMain.count == 3, "switching on warms again")
        fake.lines = [ScreenTextLine(text: "warm", box: CGRect(x: 0, y: 0.5, width: 1, height: 0.1))]
        let recognized = fake.recognizedWidths.count
        let copied = fake.texts.count
        presenter.events = []
        rig.fire(text)
        await settle("the text surface", until: { fake.answer != nil })
        fake.pick(.display(1))
        await settle("the progress notice", until: { !presenter.posts.isEmpty })
        precondition(presenter.posts == [recognizing], "a capture during the warm-up says it is recognising")
        precondition(fake.recognizedWidths.count == recognized, "and recognises nothing until the warm-up ends")
        fake.holdWarm = false
        fake.releaseWarm()
        await settle("the copied text", until: { fake.texts.count == copied + 1 })
        precondition(fake.recognizedWidths.count == recognized + 1 && fake.warmCancelled.last == false,
                     "the capture recognises once after the warm-up it waited for")
        precondition(presenter.posts.last?.id == "screenshot.text" && presenter.posts.last?.text == "warm"
                     && presenter.posts.last?.progress == nil && !presenter.events.contains("end screenshot.text"),
                     "the first line replaces the progress notice in place")

        fake.holdRecognize = true
        presenter.posts = []
        presenter.events = []
        rig.fire(text)
        await settle("the text surface", until: { fake.answer != nil })
        fake.pick(.display(1))
        await settle("a held recognition", until: { fake.recognizeGate != nil })
        precondition(presenter.posts == [recognizing], "the notice shows while recognition runs")
        rig.controller.preferences.set("screenshot", on: false)
        await settle("the switch off", until: { presenter.events.count == 2 })
        precondition(presenter.events == ["post screenshot.text", "end screenshot.text"],
                     "switching off ends the notice, and nothing else, while recognition runs")
        fake.holdRecognize = false
        fake.releaseRecognize()
        rig.controller.preferences.set("screenshot", on: true)
        await settle("the switch on", until: { rig.controller.enabledCommands.contains { $0.id == text } })
        fake.lines = [ScreenTextLine(text: "fresh", box: CGRect(x: 0, y: 0.5, width: 1, height: 0.1))]
        rig.fire(text)
        await settle("the text surface", until: { fake.answer != nil })
        fake.pick(.display(1))
        await settle("the fresh copy", until: { fake.texts.last == "fresh" })
        precondition(fake.texts.suffix(2) == ["warm", "fresh"] && presenter.posts == [recognizing, recognizing]
                     + [IslandNotice(id: "screenshot.text", symbol: "text.viewfinder", text: "fresh")]
                     && presenter.events.filter({ $0.hasPrefix("end") }).count == 1,
                     "a stopped recognition, released late, writes and posts nothing")

        let failures: [(lines: [ScreenTextLine], works: Bool, message: String)] = [
            ([ScreenTextLine](), true, "No text found in the selected area."),
            ([ScreenTextLine(text: "kept", box: CGRect(x: 0, y: 0.5, width: 1, height: 0.1))], false,
             "Could not copy to clipboard."),
        ]
        for (lines, works, failure) in failures {
            fake.lines = lines
            fake.textWorks = works
            presenter.events = []
            rig.fire(text)
            await settle("the text surface", until: { fake.answer != nil })
            fake.pick(.display(1))
            await settle("the failure", until: { presenter.events.last == "post screenshot.failed" })
            precondition(presenter.events == ["post screenshot.text", "end screenshot.text", "post screenshot.failed"]
                         && presenter.posts.last?.text == failure,
                         "a failure ends the progress notice before it reports: \(failure)")
        }
        fake.textWorks = true
        rig.finish()
    }

    @MainActor
    static func scrollingCases() async {
        let rig = Rig()
        let presenter = rig.presenter
        let area16 = ScreenshotRequest.rect(CGRect(x: 10, y: 10, width: 16, height: 30))
        let finishTitle = "Finish Scrolling Capture"
        func start(_ frames: [CGImage?], pick request: ScreenshotRequest? = area16) async {
            fake.scroll(frames)
            await settle("a scrolling surface", until: {
                if fake.answer == nil { rig.fire(scroll) }
                return fake.answer != nil
            })
            fake.pick(request)
        }
        func copied(after count: Int) async -> Data? {
            // A 20,000 px run stitches about 200 frames while this yields, so it gets more tries.
            await settle("the copy", tries: 5_000_000, until: { fake.clipboard.count == count + 1 })
            return fake.clipboard.last
        }
        func yieldALot() async { for _ in 0..<2_000 { await Task.yield() } }
        let joined = [page(offset: 0), page(offset: 42)]

        fake.granted = false
        let surfaces = fake.surfaces.count
        rig.fire(scroll)
        precondition(presenter.posts.last?.text == "Screen Recording access is required."
                     && fake.surfaces.count == surfaces && presenter.status == nil,
                     "without access it posts the failure and opens no surface")
        fake.granted = true

        await start(joined, pick: nil)
        await start(joined, pick: nil)
        precondition(fake.surfaces.count == surfaces + 2 && presenter.status == nil && fake.guides == 0,
                     "a cancelled selection goes back to idle, so the command starts again")

        rig.defaults.set(true, forKey: ScreenshotsModule.editAfterCaptureKey)
        var clips = fake.clipboard.count
        await start(joined)
        await settle("the stitched height", until: { presenter.status?.text == "162" })
        precondition(fake.regions.last == ScrollingCaptureRegion(area16, displays: fake.displays, windows: []),
                     "the run opens the picked area on its display")
        precondition(fake.guides == 1 && presenter.status?.symbol == "stop.circle"
                     && presenter.status?.label == finishTitle && presenter.statusTap != nil
                     && presenter.rows.map(\.title) == [finishTitle, "Cancel Scrolling Capture"],
                     "a run shows the guide, the stop with its height, and Finish and Cancel")
        let freezes = fake.freezes.count
        for other in [area, display, text, editLast] { rig.fire(other) }
        await yieldALot()
        precondition(fake.freezes.count == freezes && fake.edited.isEmpty && fake.surfaces.count == surfaces + 3,
                     "every other Screenshots command is ignored during a run")
        rig.fire(scroll)
        precondition(presenter.rows.isEmpty && presenter.statusTap == nil && presenter.status?.text == "162",
                     "once Finish is asked the menu goes and the stop keeps its height but takes no press")
        rig.fire(scroll)
        presenter.statusTap?()
        precondition(fake.surfaces.count == surfaces + 3, "the command while finishing is ignored")
        fake.releaseFrames()
        let first = await copied(after: clips)
        await settle("the notice", until: { presenter.posts.last?.id == "screenshot.copied" })
        precondition(pngHeight(first) == 162 && pngDPI(first).map { abs($0 - 144) < 1 } == true,
                     "the command again copies one tall Retina image")
        precondition(presenter.posts.last == IslandNotice(id: "screenshot.copied", symbol: "camera", text: "Copied"),
                     "it says Copied, as the editor does")
        precondition(presenter.status == nil && presenter.rows.isEmpty && fake.hiddenGuides == fake.guides,
                     "the result clears the stop, the menu and the guide")
        await yieldALot()
        precondition(fake.clipboard.count == clips + 1 && fake.edited.isEmpty,
                     "it ends once, and Edit after capture opens no editor for it")
        rig.defaults.removeObject(forKey: ScreenshotsModule.editAfterCaptureKey)

        for finish in ["the stop", "the Finish row"] {
            clips = fake.clipboard.count
            await start(joined)
            await settle("the stitched height", until: { presenter.status?.text == "162" })
            if finish == "the stop" { presenter.statusTap?() } else { presenter.select?("finish") }
            precondition(presenter.rows.isEmpty && presenter.statusTap == nil, "\(finish) asks Finish once")
            fake.releaseFrames()
            let data = await copied(after: clips)
            precondition(pngHeight(data) == 162, "\(finish) finishes and copies")
            await settle("the run's end", until: { presenter.status == nil })
        }

        for stop in ["Cancel", "switching off"] {
            clips = fake.clipboard.count
            let posts = presenter.posts.count
            await start(joined)
            await settle("the stitched height", until: { presenter.status?.text == "162" })
            if stop == "Cancel" {
                presenter.select?("cancel")
            } else {
                rig.controller.preferences.set("screenshot", on: false)
            }
            await settle("\(stop) clears the run", until: { presenter.status == nil })
            precondition(presenter.rows.isEmpty && fake.hiddenGuides == fake.guides, "\(stop) clears guide and menu")
            fake.releaseFrames()
            await yieldALot()
            precondition(fake.clipboard.count == clips && presenter.posts.count == posts,
                         "\(stop) copies and posts nothing, even when the stopped run's frame comes late")
            if stop == "switching off" {
                precondition(!rig.controller.run(entryID: scroll), "the command goes with the switch")
                rig.controller.preferences.set("screenshot", on: true)
                await settle("the switch on", until: { rig.controller.enabledCommands.contains { $0.id == scroll } })
            }
        }

        for (destination, folder) in [("file", "Downloads"), ("both", "Downloads")] {
            rig.defaults.set(destination, forKey: "notchcast.screenshot.destination")
            let saved = files(in: downloadsFolder).count
            clips = fake.clipboard.count
            await start(joined)
            await settle("the stitched height", until: { presenter.status?.text == "162" })
            rig.fire(scroll)
            fake.releaseFrames()
            await settle("the saved notice", until: {
                presenter.posts.last?.id == "screenshot.saved" && presenter.status == nil
            })
            precondition(presenter.posts.last?.text == "Saved to \(folder)"
                         && files(in: downloadsFolder).count == saved + 1
                         && fake.clipboard.count == clips + (destination == "both" ? 1 : 0),
                         "\(destination): saved to the screenshot folder, and says where")
            presenter.posts = []
        }
        rig.defaults.set("clipboard", forKey: "notchcast.screenshot.destination")

        // A still page with slow frames runs into the two-minute guard in about 120 of them.
        let endings: [(frames: [CGImage?], holds: Bool, seconds: Double, text: String, height: Int)] = [
            ([page(offset: 0), page(offset: 0, seed: 91)], true, 0.01,
             "Kept the part before the page changed.", 120),
            ([page(offset: 0)], false, 1, "Scrolling capture stopped at its limit.", 120),
            ((0..<250).map { page(offset: $0 * 100) }, false, 0.01,
             "Scrolling capture reached the 20,000 pixel limit.", 20_000),
        ]
        for ending in endings {
            clips = fake.clipboard.count
            fake.frameSeconds = ending.seconds
            await start(ending.frames)
            if ending.holds {
                await settle("the held run", until: { fake.frameGate != nil })
                rig.fire(scroll)
            }
            fake.releaseFrames()
            let data = await copied(after: clips)
            await settle("the notice", until: { presenter.posts.last?.id == "screenshot.copied" })
            precondition(presenter.posts.last == IslandNotice(
                            id: "screenshot.copied", symbol: "camera", text: ending.text, seconds: 4),
                         "the picture is kept and the notice says why: \(ending.text)")
            precondition(pngHeight(data) == ending.height, "\(ending.text): \(pngHeight(data) ?? -1) rows")
            await settle("the run's end", until: { presenter.status == nil })
        }
        fake.frameSeconds = 0.01

        fake.clipboardWorks = false
        await start(joined)
        await settle("the stitched height", until: { presenter.status?.text == "162" })
        rig.fire(scroll)
        fake.releaseFrames()
        await settle("the failure", until: { presenter.posts.last?.id == "screenshot.failed" })
        precondition(presenter.posts.last?.text == "Could not copy to clipboard." && presenter.status == nil,
                     "a failed clipboard write reports and clears the run")
        fake.clipboardWorks = true

        let guides = fake.guides
        await start(joined, pick: .rect(CGRect(x: 90, y: 10, width: 20, height: 10)))
        await settle("the refusal", until: { presenter.posts.last?.text == "Capture area is unavailable." })
        precondition(fake.guides == guides, "an area across two displays is refused before any run")
        presenter.posts = []
        fake.regionFails = true
        await start(joined)
        await settle("the failure", until: { presenter.posts.last?.text == "Capture area is unavailable." })
        await settle("the cleared run", until: { presenter.status == nil })
        precondition(fake.hiddenGuides == fake.guides && presenter.rows.isEmpty, "an area that will not open clears up")
        fake.regionFails = false

        rig.fire(editLast)
        await settle("the editor", until: { fake.edited.count == 1 })
        precondition(fake.edited[0].height == 162, "Edit Last Screenshot opens the last scrolling result")
        let busy = fake.surfaces.count
        rig.fire(scroll)
        await yieldALot()
        precondition(fake.surfaces.count == busy, "Scrolling Capture is ignored while the editor is open")
        rig.finish()
    }
}
