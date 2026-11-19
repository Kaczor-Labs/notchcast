// notchcast-hosted-only
// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Notchcast/HideCommandM/HideCommandMAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/HideCommandM/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/HideCommandM/Service/HideCommandMModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/HideCommandM/Service/HideCommandMSystem.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift

import AppKit
import CoreGraphics

// The shipped `live` is left out: this one stands in, so `makeModule` runs as shipped.

@MainActor
final class FakeSystem {
    var frontmost: HideCommandMTarget?
    var characters: [Int: String] = [46: "m"]
    var windowOwners: Set<Int32> = []
    var hideSucceeds = true
    var hidden: [Int32] = []
    var replayed: [[Int]] = []
}

@MainActor let fake = FakeSystem()

extension HideCommandMSystem {
    static let live = HideCommandMSystem(
        ownPID: 999,
        frontmost: { fake.frontmost },
        commandCharacter: { fake.characters[$0] },
        hasWindows: { fake.windowOwners.contains($0) },
        hide: { pid in
            guard fake.hideSucceeds else { return false }
            fake.hidden.append(pid)
            return true
        },
        replay: { pid, keyCode in fake.replayed.append([Int(pid), keyCode]) }
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
    let suite = "nc-HideCommandM-test.\(UUID())"
    let defaults: UserDefaults
    let hub: NotchcastTapHub
    let controller: NotchcastController
    var session: FakeSession?

    init() {
        defaults = UserDefaults(suiteName: suite)!
        var made: FakeSession?
        hub = NotchcastTapHub(syntheticTag: 0x54494E59, isTrusted: { true }, makeSession: {
            let session = FakeSession($0)
            made = session
            return session
        })
        controller = NotchcastController(
            addons: [HideCommandMAddon.self], defaults: defaults, hub: hub,
            dictation: FakeDictation(), presenter: FakePresenter())
        controller.start()
        session = made
    }

    func key(_ code: Int, _ flags: CGEventFlags = .maskCommand, repeat: Bool = false, synthetic: Bool = false)
        -> NotchcastTapRouter.Outcome
    {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: true)!
        event.flags = flags
        if `repeat` { event.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
        if synthetic { event.setIntegerValueField(.eventSourceUserData, value: 0x54494E59) }
        return session!.router.receive(type: .keyDown, event: event)
    }

    func finish() {
        controller.stop()
        UserDefaults().removePersistentDomain(forName: suite)
    }
}

func drain() async { try? await Task.sleep(for: .milliseconds(30)) }

@MainActor
func resetFake() {
    fake.frontmost = HideCommandMTarget(processIdentifier: 42, bundleIdentifier: "com.example.app", canHide: true)
    fake.characters = [46: "m"]
    fake.windowOwners = []
    fake.hideSucceeds = true
    fake.hidden = []
    fake.replayed = []
}

@main
enum HideCommandMModuleTests {
    @MainActor
    static func main() async {
        resetFake()
        precondition(HideCommandMPolicy.keyCode(commandCharacter: { _ in nil }) == 46, "fallback keycode")
        precondition(HideCommandMPolicy.keyCode(commandCharacter: { $0 == 41 ? "m" : "x" }) == 41, "layout keycode")

        var rig = Rig()
        precondition(rig.session?.isRunning == true, "default-on switch installs the tap")
        precondition(rig.key(46) == .swallow, "plain ⌘M is swallowed")
        await drain()
        precondition(fake.hidden == [42], "plain ⌘M hides the front app")

        for flags: CGEventFlags in [
            [.maskCommand, .maskAlternate], [.maskCommand, .maskShift], [.maskCommand, .maskControl],
            [.maskCommand, .maskSecondaryFn], [],
        ] {
            precondition(rig.key(46, flags) == .pass, "only plain ⌘ hides: \(flags.rawValue)")
        }
        precondition(rig.key(45) == .pass, "another key passes")

        fake.hidden = []
        precondition(rig.key(46, repeat: true) == .swallow, "autorepeat never reaches the app")
        await drain()
        precondition(fake.hidden.isEmpty, "autorepeat never hides again")

        precondition(rig.key(46, synthetic: true) == .pass, "our own replay is not caught again")

        precondition(rig.key(46) == .swallow)
        fake.frontmost = HideCommandMTarget(processIdentifier: 7, bundleIdentifier: nil, canHide: true)
        await drain()
        precondition(fake.hidden.isEmpty && fake.replayed.isEmpty, "a front app that changed is left alone")

        fake.frontmost = HideCommandMTarget(processIdentifier: 7, bundleIdentifier: nil, canHide: false)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        await drain()
        precondition(rig.key(46) == .pass, "an app that cannot hide gets its own ⌘M")

        fake.frontmost = HideCommandMTarget(processIdentifier: 8, bundleIdentifier: nil, canHide: true)
        guard case .reenable(let ids) = rig.session!.router.receive(type: .tapDisabledByTimeout, event: CGEvent(source: nil)!)
        else { preconditionFailure("a disable notice re-enables") }
        rig.session!.router.reenabled(ids)
        await drain()
        precondition(rig.key(46) == .swallow, "reset rereads the front app")
        fake.hideSucceeds = false
        await drain()
        precondition(fake.replayed == [[8, 46]], "a refused hide replays ⌘M to the app")

        fake.frontmost = HideCommandMTarget(processIdentifier: 999, bundleIdentifier: nil, canHide: true)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        await drain()
        precondition(rig.key(46) == .pass, "Notchcast's own windows keep ⌘M")
        rig.finish()

        resetFake()
        fake.frontmost = HideCommandMTarget(processIdentifier: 5, bundleIdentifier: "com.apple.finder", canHide: true)
        rig = Rig()
        precondition(rig.key(46) == .swallow)
        await drain()
        precondition(fake.hidden.isEmpty && fake.replayed == [[5, 46]], "windowless Finder gets ⌘M replayed")
        fake.windowOwners = [5]
        precondition(rig.key(46) == .swallow)
        await drain()
        precondition(fake.hidden == [5], "Finder with a window hides")
        rig.finish()

        resetFake()
        fake.characters = [46: ",", 41: "m"]
        rig = Rig()
        precondition(rig.key(46) == .pass, "on AZERTY 46 is ⌘, and passes")
        precondition(rig.key(41) == .swallow, "the layout's ⌘M key hides")
        rig.controller.preferences.set(HideCommandMAddon.switchID, on: false)
        await drain()
        precondition(rig.hub.subscriberCount == 0 && rig.session?.isRunning == false, "switch off removes the tap")
        rig.finish()
        print("nc-HideCommandM-module-test: PASS")
    }
}
