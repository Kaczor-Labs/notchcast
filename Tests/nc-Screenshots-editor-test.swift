// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Notchcast/Screenshots/ScreenshotsAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/Screenshots/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Screenshots/Service/ScreenshotSystem.swift
// notchcast-sources: Tinycast/Features/Notchcast/Screenshots/Service/ScreenshotsModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Screenshots/UI/CaptureEditorSession.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift

import CoreGraphics
import Foundation
import ImageIO
import SwiftUI

// #936: the editor as its command and capture start it, with a fake editor answering as the user would.
// Every wait is on an event the fakes signal, never on time.

struct ScreenshotsSettingsView: View {
    init(defaults: UserDefaults) {}
    var body: some View { EmptyView() }
}

let scratch = FileManager.default.temporaryDirectory.appending(path: "nc-Screenshots-editor-test.\(UUID())")
let downloadsFolder = scratch.appending(path: "Downloads")
let fixedDate = Date(timeIntervalSince1970: 1_763_290_800)
let editLast = "command:nc-edit-last-screenshot"
let area = "command:nc-screenshot-area"

func whiteImage(width: Int, height: Int) -> CGImage {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

/// Resumes a waiter once per signal; a signal with no waiter yet is kept for the next one.
@MainActor
final class Signals {
    private var pending: [String: Int] = [:]
    private var waiters: [String: CheckedContinuation<Void, Never>] = [:]

    func fire(_ name: String) {
        if let waiter = waiters.removeValue(forKey: name) { return waiter.resume() }
        pending[name, default: 0] += 1
    }

    func wait(_ name: String) async {
        if let count = pending[name], count > 0 { return pending[name] = count - 1 }
        await withCheckedContinuation { waiters[name] = $0 }
    }

    func count(_ name: String) -> Int { pending[name] ?? 0 }
}

@MainActor
final class EditorFake {
    let signals = Signals()
    var clipboardWorks = true
    var clipboard: [Data] = []
    var freezes = 0
    var answer: (@MainActor (ScreenshotRequest?) -> Void)?
    var edited: [CGImage] = []
    var scales: [CGFloat] = []
    var finish: (@MainActor (CaptureEditorOutcome) -> Void)?
    var closes = 0
    var saveAsNames: [String] = []
    var saveAsURL: URL?
    var questions: [String] = []
    var confirms = false
    var session: CaptureEditorSession?
    var sensitive: Result<[CGRect], any Error> = .success([])
    var holdSearch = false
    var searchGate: CheckedContinuation<Void, Never>?
    var searchScales: [CGFloat] = []
    var searchCancelled: [Bool] = []

    func findSensitive(_ scale: CGFloat) async throws -> [CGRect] {
        searchScales.append(scale)
        signals.fire("search")
        if holdSearch { await withCheckedContinuation { searchGate = $0 } }
        searchCancelled.append(Task.isCancelled)
        return try sensitive.get()
    }

    func releaseSearch() {
        holdSearch = false
        searchGate?.resume()
        searchGate = nil
    }

    func pick(_ request: ScreenshotRequest) {
        let answer = answer
        self.answer = nil
        answer?(request)
    }
}

@MainActor let fake = EditorFake()

extension ScreenshotSystem {
    static let live = ScreenshotSystem(
        grantAccess: { true },
        freeze: { _, _ in
            fake.freezes += 1
            return [ScreenshotFrozenDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 50),
                                            image: whiteImage(width: 200, height: 100))]
        },
        windows: { [] },
        freezeWindows: { _ in [:] },
        cursor: { CGPoint(x: 10, y: 10) },
        writeClipboard: { data in
            defer { fake.signals.fire("clipboard") }
            guard fake.clipboardWorks else { return false }
            fake.clipboard.append(data)
            return true
        },
        writeText: { _ in true },
        recognizeText: { _ in [] },
        warmTextRecognition: {},
        openScreenRecordingSettings: {},
        downloads: { downloadsFolder },
        chooseSaveFile: { name in
            fake.saveAsNames.append(name)
            return fake.saveAsURL
        },
        select: { _, _, _, completion in
            fake.answer = completion
            fake.signals.fire("select")
            return { fake.answer = nil }
        },
        edit: { image, scale, find, finish in
            fake.edited.append(image)
            fake.scales.append(scale)
            fake.finish = finish
            let session = CaptureEditorSession(image: image, scale: scale, find: find, finish: finish)
            fake.session = session
            fake.signals.fire("edit")
            return {
                session.end()
                fake.session = nil
                fake.closes += 1
                fake.finish = nil
                fake.signals.fire("close")
            }
        },
        findSensitiveText: { _, scale in try await fake.findSensitive(scale) }
    )
}

@MainActor
final class FakePresenter: IslandPresenting {
    var posts: [IslandNotice] = []

    func showLevel(_ level: IslandLevel) {}
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) {
        posts.append(notice)
        fake.signals.fire("notice")
    }
    func end(notice id: String) {}
    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {}
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
}

/// Reads one pixel, origin top left, from a PNG the module wrote.
func pixel(_ data: Data, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int)? {
    guard let image = CGImageSourceCreateWithData(data as CFData, nil)
        .flatMap({ CGImageSourceCreateImageAtIndex($0, 0, nil) }) else { return nil }
    var bytes = [UInt8](repeating: 0, count: 4)
    bytes.withUnsafeMutableBytes { raw in
        let context = CGContext(
            data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
    }
    return (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]))
}

func isRed(_ value: (r: Int, g: Int, b: Int)?) -> Bool {
    guard let value else { return false }
    return value.r > 200 && value.g < 120 && value.b < 120
}

func pngWidth(_ data: Data?) -> Int? {
    data.flatMap { CGImageSourceCreateWithData($0 as CFData, nil) }
        .flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }?.width
}

/// What a user does in the editor: an arrow across the middle and a word at the top left.
func annotated(_ image: CGImage) -> AnnotationDocument {
    var document = AnnotationDocument(image: image)
    document.pick(.arrow)
    document.beginDrag(at: CGPoint(x: 5, y: 45))
    document.continueDrag(to: CGPoint(x: 100, y: 45))
    document.endDrag(at: CGPoint(x: 100, y: 45), isTap: false)
    document.pick(.text)
    document.beginDrag(at: CGPoint(x: 5, y: 2))
    document.endDrag(at: CGPoint(x: 5, y: 2), isTap: true)
    document.editText("Hi")
    return document
}

struct ReaderFailed: Error {}

/// #1560: the Cover Sensitive Text button, run through the session as the editor runs it.
@MainActor
func coverSensitiveText(_ controller: NotchcastController, _ presenter: FakePresenter) async {
    let signals = fake.signals
    for name in ["notice", "close", "clipboard"] { while signals.count(name) > 0 { await signals.wait(name) } }
    precondition(controller.run(entryID: area))
    await signals.wait("select")
    fake.pick(.rect(CGRect(x: 10, y: 10, width: 60, height: 30)))
    await signals.wait("edit")
    var session = fake.session!
    fake.sensitive = .success([CGRect(x: 10, y: 10, width: 40, height: 12), CGRect(x: 10, y: 30, width: 50, height: 12)])
    session.coverSensitiveText()
    let pressed = session.search
    precondition(pressed != nil, "the button is busy while the search runs")
    session.coverSensitiveText()
    precondition(session.search == pressed, "a second press while busy starts nothing")
    await pressed?.value
    await signals.wait("search")
    let covers = session.document.marks
    precondition(covers.count == 2 && covers.allSatisfy { $0.tool == .pixelate } && session.search == nil,
                 "a press covers each find with a blur area, got \(covers)")
    precondition(fake.searchScales == [2] && session.document.tool == .select, "it searches at the capture's scale")
    session.perform(.undo)
    precondition(session.document.marks.isEmpty, "one undo takes every cover away")
    session.perform(.redo)
    session.document.beginDrag(at: CGPoint(x: 30, y: 16))
    session.document.endDrag(at: CGPoint(x: 30, y: 16), isTap: true)
    session.document.deleteSelected()
    precondition(session.document.marks.map(\.rect) == [covers[1].rect], "one cover can be deleted on its own")
    let posts = presenter.posts.count
    session.perform(.copy)
    await signals.wait("clipboard")
    await signals.wait("close")
    await signals.wait("notice")
    precondition(presenter.posts.count == posts + 1 && presenter.posts.last?.text == "Copied",
                 "exporting after a delete works as before")

    precondition(controller.run(entryID: editLast))
    await signals.wait("edit")
    session = fake.session!
    fake.sensitive = .success([])
    session.coverSensitiveText()
    await session.search?.value
    await signals.wait("search")
    await signals.wait("notice")
    precondition(presenter.posts.last?.text == "No sensitive text found." && session.document.marks.isEmpty
                 && !session.document.canUndo, "nothing found says so and adds nothing")
    fake.sensitive = .failure(ReaderFailed())
    session.coverSensitiveText()
    await session.search?.value
    await signals.wait("search")
    await signals.wait("notice")
    precondition(presenter.posts.last?.text == "Could not read text from the selection."
                 && presenter.posts.last?.isFailure == true && fake.session === session && fake.finish != nil,
                 "a failed read says so and the editor stays open")

    fake.sensitive = .success([CGRect(x: 10, y: 10, width: 40, height: 12)])
    fake.holdSearch = true
    session.coverSensitiveText()
    let stale = session.search
    await signals.wait("search")
    session.document.pick(.crop)
    session.document.beginDrag(at: CGPoint(x: 0, y: 0))
    session.document.continueDrag(to: CGPoint(x: 60, y: 30))
    session.document.endDrag(at: CGPoint(x: 60, y: 30), isTap: false)
    session.document.applyCrop()
    precondition(session.document.imageSize.width < 120, "the image was cropped while it searched")
    fake.releaseSearch()
    await stale?.value
    precondition(session.document.marks.isEmpty && session.search == nil, "a result for the uncropped image is dropped")

    fake.holdSearch = true
    session.coverSensitiveText()
    let closed = session.search
    await signals.wait("search")
    let before = presenter.posts.count
    fake.finish?(.discard)
    await signals.wait("close")
    precondition(session.search == nil, "closing the editor ends the search")
    fake.releaseSearch()
    await closed?.value
    precondition(fake.searchCancelled.last == true && session.document.marks.isEmpty && presenter.posts.count == before,
                 "the search was cancelled, and lands nothing and says nothing")
}

@main
enum ScreenshotsEditorTests {
    @MainActor
    static func main() async {
        precondition((try? FileManager.default.createDirectory(at: downloadsFolder, withIntermediateDirectories: true)) != nil)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let suite = "nc-Screenshots-editor-test.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let presenter = FakePresenter()
        let hub = NotchcastTapHub(syntheticTag: 0x54494E59, isTrusted: { true }, makeSession: { _ in
            fatalError("Screenshots declares no tap")
        })
        let controller = NotchcastController(
            addons: [ScreenshotsAddon.self], defaults: defaults, hub: hub, dictation: FakeDictation(),
            presenter: presenter, now: { fixedDate })
        controller.start()
        let signals = fake.signals
        controller.onCommandsChanged = { _ in signals.fire("commands") }

        precondition(controller.enabledCommands.map(\.id).contains(editLast), "Edit Last Screenshot ships on")
        precondition(controller.run(entryID: editLast), "its command resolves")
        precondition(presenter.posts.last?.text == "No screenshot to edit yet." && fake.edited.isEmpty,
                     "with no capture yet it says so and opens nothing")
        await signals.wait("notice")

        precondition(controller.run(entryID: area))
        await signals.wait("select")
        fake.pick(.rect(CGRect(x: 10, y: 10, width: 60, height: 30)))
        await signals.wait("clipboard")
        precondition(fake.clipboard.count == 1 && fake.edited.isEmpty, "editing off: a capture is copied as before")

        precondition(controller.run(entryID: editLast))
        await signals.wait("edit")
        precondition(fake.edited.last?.width == 120 && fake.edited.last?.height == 60, "it opens the last capture")
        precondition(controller.run(entryID: area) && fake.freezes == 1, "a capture while editing is ignored")
        fake.finish?(.discard)
        await signals.wait("close")
        precondition(fake.clipboard.count == 1 && presenter.posts.count == 1, "Esc discards: nothing written")

        defaults.set(true, forKey: "notchcast.screenshot.editAfterCapture")
        precondition(controller.run(entryID: area))
        await signals.wait("select")
        fake.pick(.rect(CGRect(x: 10, y: 10, width: 60, height: 30)))
        await signals.wait("edit")
        precondition(fake.clipboard.count == 1 && fake.edited.count == 2, "edit after capture opens it before output")
        let capture = fake.edited.last!
        fake.finish?(.copy(annotated(capture)))
        await signals.wait("clipboard")
        await signals.wait("close")
        await signals.wait("notice")
        precondition(presenter.posts.last?.text == "Copied", "the island says Copied")
        let pasted = fake.clipboard.last!
        precondition(fake.clipboard.count == 2 && pngWidth(pasted) == 120, "Copy puts the whole capture on the clipboard")
        precondition(isRed(pixel(pasted, 60, 45)), "the pasted image has the arrow")
        let text = (2..<18).flatMap { y in (5..<25).map { x in pixel(pasted, x, y) } }.filter(isRed).count
        precondition(text > 10, "and the text still being typed, got \(text) red pixels")

        precondition(controller.run(entryID: editLast))
        await signals.wait("edit")
        precondition(fake.edited.count == 3 && fake.edited.last!.width == 120, "the original is kept to edit again")
        precondition(fake.scales == [2, 2, 2], "the editor gets the scale of the display captured, got \(fake.scales)")
        fake.clipboardWorks = false
        fake.finish?(.copy(annotated(capture)))
        await signals.wait("notice")
        precondition(presenter.posts.last?.text == "Could not copy to clipboard." && fake.closes == 2,
                     "a failed copy reports and leaves the editor open with its marks")
        fake.clipboardWorks = true
        fake.finish?(.save(annotated(capture)))
        await signals.wait("close")
        let saved = (try? FileManager.default.contentsOfDirectory(atPath: downloadsFolder.path(percentEncoded: false))) ?? []
        let name = ScreenshotFileName.name(date: fixedDate, timeZone: .current)
        precondition(saved == [name], "Save writes to the screenshots folder, v1 name, got \(saved)")
        let file = try? Data(contentsOf: downloadsFolder.appending(path: name))
        precondition(file.map { isRed(pixel($0, 60, 45)) } == true, "the saved file has the arrow")
        precondition(fake.clipboard.count == 2, "Save leaves the clipboard alone")
        await signals.wait("notice")
        precondition(presenter.posts.last?.text == "Saved to Downloads", "the island names the folder")

        controller.context(forSwitch: "screenshot")?.presentDestructiveQuestion = { title, _, _, _ in
            fake.questions.append(title)
            fake.signals.fire("question")
            return fake.confirms
        }
        precondition(controller.run(entryID: editLast))
        await signals.wait("edit")
        let closes = fake.closes
        fake.finish?(.close(AnnotationDocument(image: fake.edited.last!)))
        await signals.wait("close")
        precondition(fake.questions.isEmpty && fake.closes == closes + 1, "closing with nothing drawn asks nothing")
        precondition(controller.run(entryID: editLast))
        await signals.wait("edit")
        fake.finish?(.close(annotated(capture)))
        await signals.wait("question")
        precondition(fake.questions == ["Discard this screenshot's edits?"] && fake.finish != nil
                     && fake.closes == closes + 1, "closing with marks asks, and Cancel keeps the editor open")
        var exported = annotated(capture)
        exported.markExported()
        fake.finish?(.close(exported))
        await signals.wait("close")
        precondition(fake.questions.count == 1, "work already copied, saved or dragged out closes without asking")
        precondition(controller.run(entryID: editLast))
        await signals.wait("edit")
        fake.confirms = true
        fake.finish?(.close(annotated(capture)))
        await signals.wait("question")
        await signals.wait("close")
        let files = { (try? FileManager.default.contentsOfDirectory(atPath: downloadsFolder.path(percentEncoded: false))) ?? [] }
        precondition(fake.questions.count == 2 && fake.clipboard.count == 2 && files() == [name],
                     "Discard closes it and writes nothing")

        precondition(controller.run(entryID: editLast))
        await signals.wait("edit")
        fake.saveAsURL = nil
        fake.finish?(.saveAs(annotated(capture)))
        precondition(fake.saveAsNames == [name] && fake.finish != nil, "Save As offers the v1 name; Cancel keeps it open")
        let chosen = scratch.appending(path: "Chosen")
        precondition((try? FileManager.default.createDirectory(at: chosen, withIntermediateDirectories: true)) != nil)
        fake.saveAsURL = chosen.appending(path: "Picked.png")
        fake.finish?(.saveAs(annotated(capture)))
        await signals.wait("close")
        await signals.wait("notice")
        let picked = try? Data(contentsOf: chosen.appending(path: "Picked.png"))
        precondition(picked.map { isRed(pixel($0, 60, 45)) } == true && files() == [name],
                     "Save As writes where the panel points, with the arrow")
        precondition(presenter.posts.last?.text == "Saved to Chosen", "and the island names that folder")

        precondition(controller.run(entryID: editLast))
        await signals.wait("edit")
        controller.preferences.set("screenshot", on: false)
        await signals.wait("close")
        await signals.wait("commands")
        precondition(fake.finish == nil && !controller.run(entryID: editLast), "switching off closes the editor")
        controller.preferences.set("screenshot", on: true)
        await signals.wait("commands")
        precondition(controller.run(entryID: editLast) && presenter.posts.last?.text == "No screenshot to edit yet.",
                     "and forgets the capture")

        await coverSensitiveText(controller, presenter)
        controller.stop()
        print("nc-Screenshots-editor-test: ok")
    }
}
