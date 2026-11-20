// notchcast-hosted-only
// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Notchcast/FinderTools/FinderToolsAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/FinderTools/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/FinderTools/Service/FinderToolsModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/FinderTools/Service/FinderToolsSystem.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift

import AppKit
import CoreGraphics
import Synchronization

// The shipped `live` is left out: this one stands in, so `makeModule` runs as shipped.

enum Paster { static let tinycastEventTag: Int64 = 0x54494E59 }

let finderPID: Int32 = 77
let selectedList: [FinderToolsFocus.Element] = [.init(role: "AXOutline", hasSelection: true), .init(role: "AXWindow")]
let focusChain = Mutex<[FinderToolsFocus.Element]?>(selectedList)
let safariPID: Int32 = 99
let ownPID = ProcessInfo.processInfo.processIdentifier

@MainActor
final class FakeSystem {
    var frontmost: Int32? = finderPID
    /// The app in front while Finder is not.
    var other: Int32 = safariPID
    var changeCount = 10
    var posted: [String] = []
}

@MainActor let fake = FakeSystem()

extension FinderToolsSystem {
    static let live = FinderToolsSystem(
        syntheticTag: Paster.tinycastEventTag,
        frontmostFinderPID: { fake.frontmost },
        frontmostPID: { fake.frontmost ?? fake.other },
        changeCount: { fake.changeCount },
        commandCharacter: { [7: "x", 8: "c", 9: "v", 15: "r"][$0] },
        focus: { _ in focusChain.withLock { $0 } },
        post: { pid, keyCode, modifiers in fake.posted.append("\(pid):\(keyCode):\(modifiers.rawValue)") }
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
final class FakePresenter: IslandPresenting {
    func showLevel(_ level: IslandLevel) {}
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) {}
    func end(notice id: String) {}
    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {}
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
}

@MainActor
final class Rig {
    let suite = "nc-FinderTools-test.\(UUID())"
    let defaults: UserDefaults
    let hub: NotchcastTapHub
    let controller: NotchcastController
    var sessions: [FakeSession] = []

    init(enabled: [String]) {
        defaults = UserDefaults(suiteName: suite)!
        for id in enabled { defaults.set(true, forKey: id) }
        var made: [FakeSession] = []
        hub = NotchcastTapHub(syntheticTag: Paster.tinycastEventTag, isTrusted: { true }, makeSession: {
            let session = FakeSession($0)
            made.append(session)
            return session
        })
        controller = NotchcastController(
            addons: [FinderToolsAddon.self], defaults: defaults, hub: hub,
            dictation: FakeDictation(), presenter: FakePresenter())
        controller.start()
        sessions = made
    }

    var module: FinderToolsModule? {
        controller.context(forSwitch: FinderToolsAddon.cutPasteSwitchID)?.module(FinderToolsModule.self)
    }

    var session: FakeSession? { sessions.last { $0.isRunning } }

    @discardableResult
    func key(_ code: Int, _ flags: CGEventFlags = .maskCommand, down: Bool = true, synthetic: Bool = false)
        -> NotchcastTapRouter.Outcome
    {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: down)!
        event.flags = flags
        if synthetic { event.setIntegerValueField(.eventSourceUserData, value: Paster.tinycastEventTag) }
        return session!.router.receive(type: down ? .keyDown : .keyUp, event: event)
    }

    /// Hands the tap's requests to the module and waits for its queue, with no clock involved.
    func settle() async {
        module?.pump()
        await module?.worker?.value
    }

    /// The module's own hook: the workspace's activation notice, then its hop back to the main actor.
    func activate(_ frontmost: Int32?) async {
        fake.frontmost = frontmost
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification, object: NSWorkspace.shared)
        await Task.yield()
        await settle()
    }

    func finish() {
        controller.stop()
        UserDefaults().removePersistentDomain(forName: suite)
    }
}

@main
enum FinderToolsModuleTests {
    @MainActor
    static func main() async {
        let off = Rig(enabled: [])
        precondition(off.session == nil, "both switches off by default: no tap")
        precondition(off.module == nil, "no module while both are off")
        off.finish()

        let rig = Rig(enabled: [FinderToolsAddon.cutPasteSwitchID])
        precondition(rig.session != nil, "cut and paste on installs the tap")
        precondition(rig.module != nil, "and builds the module")

        precondition(rig.key(7) == .swallow, "⌘X in Finder is swallowed")
        precondition(rig.key(7, down: false) == .swallow, "its key-up too")
        await rig.settle()
        precondition(fake.posted == ["77:8:1"], "Finder gets its own ⌘C: \(fake.posted)")
        fake.changeCount = 11

        precondition(rig.key(9) == .swallow, "⌘V with a pending cut is swallowed")
        precondition(rig.key(9, down: false) == .swallow, "its key-up too")
        await rig.settle()
        precondition(fake.posted.last == "77:9:5", "Finder gets Move Item Here, ⌥⌘V: \(fake.posted)")
        precondition(rig.key(9) == .pass, "one paste per cut")
        rig.key(9, down: false)

        precondition(rig.key(7, synthetic: true) == .pass, "our own events pass")

        fake.posted = []
        rig.key(7)
        rig.key(7, down: false)
        focusChain.withLock { $0 = [.init(role: "AXTextField"), .init(role: "AXWindow")] }
        await rig.settle()
        precondition(fake.posted == ["77:7:1"], "in the rename field ⌘X goes back as text cut: \(fake.posted)")

        fake.posted = []
        focusChain.withLock { $0 = [.init(role: "AXOutline"), .init(role: "AXWindow")] }
        rig.key(7)
        rig.key(7, down: false)
        await rig.settle()
        precondition(fake.posted == ["77:7:1"], "nothing selected: Finder gets the original ⌘X: \(fake.posted)")
        fake.changeCount = 12
        precondition(rig.key(9) == .pass, "so a later ordinary copy is pasted, never moved")
        rig.key(9, down: false)
        focusChain.withLock { $0 = selectedList }

        fake.posted = []
        rig.key(7)
        fake.frontmost = nil
        await rig.settle()
        precondition(fake.posted == ["99:7:1"], "Finder left the front: the key goes to the app now in front: \(fake.posted)")
        rig.key(7, down: false)

        fake.posted = []
        precondition(rig.controller.run(entryID: "command:nc-finder-cut"), "the cut command runs by hotkey in another app")
        await rig.activate(finderPID)
        precondition(fake.posted.isEmpty, "and is dropped: a later switch to Finder sends nothing: \(fake.posted)")

        fake.frontmost = nil
        fake.other = ownPID
        precondition(rig.controller.run(entryID: "command:nc-finder-cut"), "the cut command runs with Notchcast in front")
        precondition(fake.posted.isEmpty, "and waits for Finder")
        await rig.activate(finderPID)
        precondition(fake.posted == ["77:8:1"], "Finder activated next: the command copies: \(fake.posted)")

        fake.posted = []
        fake.frontmost = nil
        precondition(rig.controller.run(entryID: "command:nc-finder-cut"), "the cut command waits again")
        fake.other = safariPID
        await rig.activate(nil)
        await rig.activate(finderPID)
        precondition(fake.posted.isEmpty, "another app came first: the wait is over, nothing sent: \(fake.posted)")
        rig.module?.run(.cut)
        await rig.settle()
        precondition(fake.posted == ["77:8:1"], "with Finder frontmost the command copies: \(fake.posted)")
        precondition(!rig.controller.run(entryID: "command:nc-finder-rename"), "rename command off with its switch")
        rig.finish()

        let rename = Rig(enabled: ["finderRename"])
        fake.posted = []
        precondition(rename.session == nil, "rename alone installs no tap, so ⌃⌥⇧⌘R and ⌘X pass")
        precondition(rename.controller.run(entryID: "command:nc-finder-rename"), "the rename command runs")
        await rename.settle()
        precondition(fake.posted == ["77:36:0"], "rename presses Return in Finder: \(fake.posted)")
        rename.finish()
        print("PASS: Finder tools module wires taps, Finder's keys, focus, frontmost checks and commands")
    }
}
