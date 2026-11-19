// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Notchcast/Screenshots/ScreenshotsAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/Screenshots/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Screenshots/Service/ScreenshotSystem.swift
// notchcast-sources: Tinycast/Features/Notchcast/Screenshots/Service/ScreenshotsModule.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift

import CoreGraphics
import Foundation
import ImageIO
import SwiftUI

// The shipped `live` and settings UI are left out: these stand in, so `makeModule` runs as shipped.

struct ScreenshotsSettingsView: View {
    init(defaults: UserDefaults) {}
    var body: some View { EmptyView() }
}

let scratch = FileManager.default.temporaryDirectory.appending(path: "nc-Screenshots-module-test.\(UUID())")
let desktopFolder = scratch.appending(path: "Desktop")
let chosenFolder = scratch.appending(path: "Chosen")
let fixedDate = Date(timeIntervalSince1970: 1_763_290_800)

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

    func recognize(_ image: CGImage) -> [ScreenTextLine] {
        recognizedWidths.append(image.width)
        return lines
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
        recognizeText: { image in await fake.recognize(image) },
        openScreenRecordingSettings: { fake.settingsOpened += 1 },
        desktop: { desktopFolder },
        select: { frozen, windows, completion in
            fake.surfaces.append((frozen.map(\.id), windows.map(\.id)))
            fake.answer = completion
            return {
                fake.closes += 1
                fake.pick(nil)
            }
        }
    )
}

@MainActor
final class FakePresenter: IslandPresenting {
    var posts: [IslandNotice] = []

    func showLevel(_ level: IslandLevel) {}
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) { posts.append(notice) }
    func end(notice id: String) {}
    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {}
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
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
let text = "command:nc-capture-text"

func drain() async { try? await Task.sleep(for: .milliseconds(120)) }

func files(in folder: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []).sorted()
}

func isPNG(_ data: Data?) -> Bool { data?.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]) }

func pngWidth(_ data: Data?) -> Int? {
    data.flatMap { CGImageSourceCreateWithData($0 as CFData, nil) }
        .flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }?.width
}

@main
enum ScreenshotsModuleTests {
    @MainActor
    static func main() async {
        precondition((try? FileManager.default.createDirectory(at: desktopFolder, withIntermediateDirectories: true)) != nil)
        precondition((try? FileManager.default.createDirectory(at: chosenFolder, withIntermediateDirectories: true)) != nil)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let rig = Rig()
        let presenter = rig.presenter

        precondition(ScreenshotsAddon.switches.map(\.id) == ["screenshot"], "v1 switch id")
        precondition(ScreenshotsAddon.commands.map(\.id) == [area, display, text], "frozen command ids")
        precondition(ScreenshotsAddon.commands.map { "hotkey." + $0.id }
                     == ["hotkey.command:nc-screenshot-area", "hotkey.command:nc-screenshot-display",
                         "hotkey.command:nc-capture-text"], "each stored binding names its command")
        precondition(rig.controller.enabledCommands.map(\.id) == [area, display, text], "on by default")

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
        precondition(files(in: desktopFolder).isEmpty && presenter.posts.isEmpty, "no file by default")

        precondition(rig.controller.run(entryID: area))
        await drain()
        precondition(fake.frozenWindows.last == [51], "only pickable windows are frozen, before selection")
        fake.windowWidth = 31
        fake.closedWindows = [51]
        fake.pick(.window(51))
        await drain()
        precondition(fake.clipboard.count == 2 && pngWidth(fake.clipboard.last) == 30,
                     "a click saves the frozen window, even after it changed or closed")
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
        precondition(files(in: desktopFolder) == [first], "no folder set means the Desktop, v1 name")
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

        rig.fire(area)
        await drain()
        let shots = fake.clipboard.count
        rig.controller.preferences.set("screenshot", on: false)
        await drain()
        precondition(fake.closes == 1 && fake.answer == nil, "switching off closes the surface")
        precondition(fake.clipboard.count == shots && !rig.controller.run(entryID: area), "and its commands go")

        rig.finish()
        print("nc-Screenshots-module-test: ok")
    }
}
