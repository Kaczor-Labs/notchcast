// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Notchcast/PasteImage/PasteImageAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/PasteImage/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/PasteImage/Service/PasteImageModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/PasteImage/Service/PasteImageSystem.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift

import AppKit
import CoreGraphics
import Synchronization

// The shipped `live` is left out: this one stands in, so `makeModule` runs as shipped.

let png = PasteImageClip(data: Data([0x89, 0x50]), isPNG: true)
let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

@MainActor
final class FakeSystem {
    var finder: Int32? = 7
    var finderReads = 0
    var characters: [Int: String] = [9: "v"]
    var types = ["public.png"]
    var image: PasteImageClip? = png
    var role: String?
    var hold = false
    var saveWorks = true
    var saves: [Date] = []
    var replays: [[Int]] = []

    func reset() {
        finder = 7; finderReads = 0; characters = [9: "v"]; types = ["public.png"]; image = png; role = nil
        hold = false; saveWorks = true; saves = []; replays = []
    }

    func save(_ clip: PasteImageClip, _ date: Date) async -> Bool {
        precondition(clip == png, "the clipboard image is what is saved")
        saves.append(date)
        while hold && !Task.isCancelled { await Task.yield() }
        return saveWorks
    }
}

@MainActor let fake = FakeSystem()
let fakeTypes = Mutex<[String]>(["public.png"])

extension PasteImageSystem {
    static let live = PasteImageSystem(
        frontFinder: {
            fake.finderReads += 1
            return fake.finder
        },
        commandCharacter: { fake.characters[$0] },
        clipboardTypes: { fakeTypes.withLock { $0 } },
        clipboardImage: { fake.image },
        focusedRole: { _ in await fake.role },
        save: { await fake.save($0, $1) },
        replay: { pid, keyCode in fake.replays.append([Int(pid), keyCode]) }
    )
}

final class FakeSession: NotchcastTapSession {
    let mask: CGEventMask
    let options: CGEventTapOptions
    let router: NotchcastTapRouter
    var isRunning = true

    init(_ request: NotchcastTapSessionRequest) {
        mask = request.mask
        options = request.options
        router = request.router
    }

    func stop() { isRunning = false }
}

@MainActor
final class RecordingPresenter: IslandPresenting {
    var posts: [IslandNotice] = []
    func showLevel(_ level: IslandLevel) {}
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) { posts.append(notice) }
    func end(notice id: String) {}
    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {}
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
}

/// Yields until the condition holds, so no wall-clock wait is involved.
@MainActor
func until(_ label: String, _ condition: () -> Bool) async {
    for _ in 0..<10_000 where !condition() { await Task.yield() }
    precondition(condition(), "timed out: \(label)")
}

@MainActor
final class Rig {
    let suite = "nc-PasteImage-module-test.\(UUID())"
    let defaults: UserDefaults
    let presenter = RecordingPresenter()
    let hub: NotchcastTapHub
    let controller: NotchcastController
    var session: FakeSession?

    init(on: Bool = true) {
        defaults = UserDefaults(suiteName: suite)!
        defaults.set(on, forKey: "pasteImage")
        var made: FakeSession?
        hub = NotchcastTapHub(syntheticTag: 0x54494E59, isTrusted: { true }, makeSession: {
            let session = FakeSession($0)
            made = session
            return session
        })
        controller = NotchcastController(
            addons: [PasteImageAddon.self], defaults: defaults, hub: hub, dictation: FakeDictation(),
            presenter: presenter, now: { fixedDate })
        controller.start()
        session = made
    }

    var module: PasteImageModule? { controller.context(forSwitch: "pasteImage")?.module(PasteImageModule.self) }

    func send(_ code: Int, down: Bool = true, flags: CGEventFlags = .maskCommand, repeat: Bool = false,
              synthetic: Bool = false) -> NotchcastTapRouter.Outcome {
        fakeTypes.withLock { $0 = fake.types }
        let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: down)!
        event.flags = flags
        if `repeat` { event.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
        if synthetic { event.setIntegerValueField(.eventSourceUserData, value: 0x54494E59) }
        return session!.router.receive(type: down ? .keyDown : .keyUp, event: event)
    }

    /// One ⌘V that the add-on takes, run until its outcome shows and its work is done.
    func paste(_ label: String, until outcome: () -> Bool) async {
        precondition(send(9) == .swallow, "\(label): ⌘V is taken")
        await until(label) { module?.work == nil && outcome() }
        precondition(send(9, down: false) == .swallow, "\(label): its key-up is swallowed")
    }

    func activate() async {
        let reads = fake.finderReads
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        await until("activation rereads Finder") { fake.finderReads > reads }
    }

    func finish() {
        controller.stop()
        UserDefaults().removePersistentDomain(forName: suite)
    }
}

@main
enum PasteImageModuleTests {
    @MainActor
    static func main() async {
        let switchInfo = PasteImageAddon.switches
        precondition(switchInfo.map(\.id) == ["pasteImage"], "v1 switch id")
        precondition(switchInfo[0].defaultEnabled == false, "off by default")
        precondition(switchInfo[0].category == .filesDownloads, "Files & Downloads")
        precondition(switchInfo[0].requiredGrants == [.accessibility], "key handling needs Accessibility")

        fake.reset()
        var rig = Rig(on: false)
        precondition(rig.module == nil && rig.hub.subscriberCount == 0, "switch off: no module, no tap")
        rig.finish()

        rig = Rig()
        await rig.paste("acceptance 1") { fake.saves.count == 1 }
        precondition(fake.saves == [fixedDate], "the image is saved, named from the injected clock")
        precondition(rig.presenter.posts.isEmpty && fake.replays.isEmpty, "a saved paste posts nothing")

        precondition(rig.send(9, repeat: true) == .pass, "a repeat after the key-up passes")
        precondition(rig.send(9, synthetic: true) == .pass, "our own replayed ⌘V is never caught")
        precondition(rig.send(9, flags: [.maskCommand, .maskShift]) == .pass, "⌘⇧V passes")
        precondition(rig.send(8) == .pass, "⌘C passes")

        fake.types = ["public.file-url", "public.tiff"]
        precondition(rig.send(9) == .pass && rig.send(9, down: false) == .pass, "acceptance 2: copied files")
        fake.types = ["public.png"]

        fake.role = "AXTextField"
        await rig.paste("acceptance 3") { fake.replays.count == 1 }
        precondition(fake.replays == [[7, 9]] && fake.saves.count == 1, "a rename field gets a text ⌘V")
        fake.role = nil

        fake.image = nil
        await rig.paste("clipboard changed") { fake.replays.count == 2 }
        precondition(fake.replays == [[7, 9], [7, 9]] && fake.saves.count == 1, "no image left: a plain ⌘V")
        fake.image = png

        fake.hold = true
        precondition(rig.send(9) == .swallow, "a held save")
        await until("save starts") { fake.saves.count == 2 }
        precondition(rig.send(9) == .pass, "a ⌘V while saving is a normal ⌘V")
        precondition(rig.send(9, repeat: true) == .pass && rig.send(9, down: false) == .pass, "and passes whole")
        fake.saveWorks = false
        fake.hold = false
        await until("failure shows") { rig.module?.work == nil && !rig.presenter.posts.isEmpty }
        let notice = rig.presenter.posts[0]
        precondition(notice.isFailure && notice.id == "pasteImage", "one failure notice")
        precondition(
            notice.text == "Cannot paste image here. Choose a writable Finder folder and allow Automation access "
                + "in System Settings.", "the issue's failure text: \(notice.text)")
        fake.saveWorks = true
        await rig.paste("after a failure") { fake.saves.count == 3 }
        precondition(rig.presenter.posts.count == 1, "the next paste works")

        let reads = fake.finderReads
        fake.finder = nil
        await rig.paste("Finder left") { fake.finderReads > reads }
        precondition(fake.saves.count == 3 && fake.replays.count == 2, "Finder no longer in front: nothing happens")

        await rig.activate()
        precondition(rig.send(9) == .pass, "outside Finder ⌘V passes")
        fake.finder = 7
        await rig.activate()

        fake.hold = true
        precondition(rig.send(9) == .swallow, "a held key")
        await until("held save") { fake.saves.count == 4 }
        let beforeReset = fake.finderReads
        guard case .reenable(let ids) = rig.session!.router.receive(
            type: .tapDisabledByTimeout, event: CGEvent(source: nil)!)
        else { preconditionFailure("a disable notice re-enables") }
        rig.session!.router.reenabled(ids)
        await until("reset rereads Finder") { fake.finderReads > beforeReset }
        precondition(rig.send(9, down: false) == .pass, "after lost events no key-up is held")

        let task = rig.module?.work
        precondition(task != nil, "still saving")
        rig.controller.preferences.set("pasteImage", on: false)
        await until("switch off") { rig.module == nil }
        await task?.value
        precondition(rig.presenter.posts.count == 1, "a paste cut off by switch-off posts nothing")
        precondition(rig.hub.subscriberCount == 0 && rig.session?.isRunning == false, "switch off removes the tap")
        rig.finish()

        fake.reset()
        fake.characters = [9: "k", 47: "v"]
        rig = Rig()
        precondition(rig.send(9) == .pass, "on Dvorak ANSI V is ⌘K")
        precondition(rig.send(47) == .swallow, "the layout's ⌘V key pastes")
        await until("layout paste") { rig.module?.work == nil && fake.saves.count == 1 }
        precondition(fake.replays.isEmpty, "saved, not replayed")
        rig.finish()
        print("nc-PasteImage-module-test: PASS")
    }
}
