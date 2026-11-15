// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Notchcast/ShowDesktop/ShowDesktopAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/ShowDesktop/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/ShowDesktop/Service/ShowDesktopModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/ShowDesktop/Service/ShowDesktopSystem.swift

import AppKit
import CoreGraphics

// The shipped `live` is left out: this one stands in, so `makeModule` runs as shipped.

@MainActor
final class FakeSystem {
    var standardFunctionKeys = false
    var fnStateReads = 0
    var toggles = 0
}

@MainActor let fake = FakeSystem()

extension ShowDesktopSystem {
    static let live = ShowDesktopSystem(
        standardFunctionKeys: {
            fake.fnStateReads += 1
            return fake.standardFunctionKeys
        },
        toggleDesktop: { fake.toggles += 1 }
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
final class FakePresenter: NotchcastPresenting {
    func showLevel(_ level: NotchcastLevel) {}
    func post(_ notice: NotchcastNotice) {}
    func end(_ noticeID: UUID) {}
    func setStatus(_ status: NotchcastStatus?, owner: String) {}
    func setMenuRows(_ rows: [NotchcastMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
}

@MainActor
final class Rig {
    let suite = "nc-ShowDesktop-test.\(UUID())"
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
            addons: [ShowDesktopAddon.self], defaults: defaults, hub: hub, presenter: FakePresenter())
        controller.start()
        session = made
    }

    func key(_ code: Int, _ flags: CGEventFlags = [], synthetic: Bool = false) -> NotchcastTapRouter.Outcome {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: true)!
        event.flags = flags
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
func resetFake(standardFunctionKeys: Bool) {
    fake.standardFunctionKeys = standardFunctionKeys
    fake.fnStateReads = 0
    fake.toggles = 0
}

@main
enum ShowDesktopModuleTests {
    @MainActor
    static func main() async {
        precondition(ShowDesktopPolicy.acts(keyCode: 160, flags: [], standardFunctionKeys: false), "160")
        precondition(ShowDesktopPolicy.acts(keyCode: 160, flags: .maskSecondaryFn, standardFunctionKeys: true),
                     "fn alone is not a modifier")
        precondition(!ShowDesktopPolicy.acts(keyCode: 99, flags: [], standardFunctionKeys: false), "99 needs fnState")
        precondition(ShowDesktopPolicy.acts(keyCode: 99, flags: [], standardFunctionKeys: true), "99 with fnState")

        resetFake(standardFunctionKeys: false)
        var rig = Rig()
        precondition(rig.session?.isRunning == true, "tap runs while the switch is on")
        precondition(rig.key(160) == .swallow, "F3 swallows")
        await drain()
        precondition(fake.toggles == 1, "first F3 shows the desktop")
        precondition(rig.key(160) == .swallow, "second F3 swallows")
        await drain()
        precondition(fake.toggles == 2, "second F3 toggles the Dock back")
        for flags: CGEventFlags in [.maskCommand, .maskShift, .maskAlternate, .maskControl] {
            precondition(rig.key(160, flags) == .pass, "modified F3 passes: \(flags.rawValue)")
        }
        precondition(rig.key(99) == .pass, "99 passes with fnState off")
        precondition(rig.key(160, synthetic: true) == .pass, "our own synthetic key passes")
        await drain()
        precondition(fake.toggles == 2, "nothing passed through acted")
        precondition(fake.fnStateReads == 1, "fnState is read once at start")
        rig.finish()

        resetFake(standardFunctionKeys: true)
        rig = Rig()
        precondition(rig.key(99) == .swallow, "99 swallows with fnState on")
        precondition(rig.key(160) == .swallow, "160 still acts with fnState on")
        await drain()
        precondition(fake.toggles == 2, "both keys toggle with fnState on")

        precondition(rig.key(160) == .swallow, "queued before stop")
        rig.controller.stop()
        await drain()
        precondition(fake.toggles == 2, "a press queued before stop never acts")
        rig.finish()

        resetFake(standardFunctionKeys: false)
        rig = Rig()
        rig.controller.preferences.set(ShowDesktopAddon.switchID, on: false)
        await drain()
        precondition(rig.hub.subscriberCount == 0, "switch off unsubscribes")
        precondition(rig.session?.isRunning == false, "switch off stops the tap")
        rig.finish()

        print("nc-ShowDesktop-module-test: PASS")
    }
}
