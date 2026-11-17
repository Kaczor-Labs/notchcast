// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Features/Island/Model/VolumeLevel+Island.swift
// notchcast-sources: Tinycast/Features/SystemActions/Model/VolumeLevel.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Notchcast/DisplaySound/DisplaySoundAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/DisplaySound/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/DisplaySound/Service/DisplaySoundModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/DisplaySound/Service/DisplaySoundSystem.swift
// notchcast-sources: Tinycast/Features/Notchcast/DisplaySound/Service/BrightnessDDCChannel.swift
// notchcast-sources: Tinycast/Features/Notchcast/DisplaySound/Service/BrightnessDisplayService.swift
// notchcast-sources: Tinycast/Features/Notchcast/DisplaySound/Service/BrightnessController.swift
// notchcast-sources: Tinycast/Features/Notchcast/DisplaySound/Service/DisplaySoundRecovery.swift
// notchcast-sources: Tinycast/Features/Notchcast/DisplaySound/Service/AudioLevelAccess.swift
// notchcast-sources: Tinycast/Features/Notchcast/DisplaySound/Service/AudioLevelsService.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift

import AppKit
import CoreGraphics
import Synchronization
import SwiftUI

// The shipped `live` and settings view are left out: these stand in, so `makeModule` runs as shipped.

struct BrightnessSettingsView: View {
    init(context: NotchcastContext) {}
    var body: some View { EmptyView() }
}

struct Hardware {
    var system: Double? = 0.5
    var gamma = BrightnessGamma(red: [0, 1], green: [0, 1], blue: [0, 1])
    var volume = 0.5
    var muted: Bool? = false
    var settable = true
    var refusesMute = false
    var online = true
}

let rack = Mutex(Hardware())
func hw<T: Sendable>(_ body: (inout Hardware) -> T) -> T { rack.withLock { body(&$0) } }
let baseline = BrightnessGamma(red: [0, 1], green: [0, 1], blue: [0, 1])

@MainActor
final class Fake {
    var cursorOnDisplay = true
    var functionKeys = true
    var replayed: [MediaLevelKey] = []
    var levels: [IslandLevel] = []
    var notices: [IslandNotice] = []
    var displayChanged: (@MainActor @Sendable (Bool) -> Void)?
    var displayWatchCount = 0
}

@MainActor let fake = Fake()

extension DisplaySoundSystem {
    static let live = DisplaySoundSystem(
        displays: .init(
            online: { hw { $0.online ? [9] : [] } },
            uuid: { _ in "display-9" },
            isActive: { _ in true },
            isBuiltIn: { _ in true },
            readSystem: { _ in hw { $0.system } },
            writeSystem: { _, value in hw { $0.system = value; return true } },
            discoverDDC: { [:] },
            readGamma: { _ in hw { $0.gamma } },
            writeGamma: { _, gamma in hw { $0.gamma = gamma; return true } }),
        audio: .init(
            defaultOutput: { 1 },
            has: { _, control in control == .virtualMain },
            stereoChannels: { _ in nil },
            volume: { _, _ in hw { $0.volume } },
            canSetVolume: { _, _ in hw { $0.settable } },
            setVolume: { _, _, value in hw { $0.volume = value; return true } },
            muted: { _ in hw { $0.muted } },
            canSetMute: { _ in true },
            setMuted: { _, value in hw {
                guard !$0.refusesMute else { return false }
                $0.muted = value
                return true
            } }),
        sleep: { try await Task.sleep(for: $0 / 1000) },
        screenNames: { [9: "Built-in"] },
        displayContaining: { _, ids in fake.cursorOnDisplay ? ids.first : nil },
        functionKeysAdjustBrightness: { fake.functionKeys },
        replay: { key, _ in fake.replayed.append(key) },
        watchDisplays: { handler in
            fake.displayWatchCount += 1
            fake.displayChanged = handler
            return [NSObject()]
        },
        watchAudio: { _, _ in [] })
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
    func showLevel(_ level: IslandLevel) { fake.levels.append(level) }
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) { fake.notices.append(notice) }
    func end(notice id: String) {}
    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {}
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
}

let tag: Int64 = 0x54494E59

@MainActor
final class SessionLog {
    var all: [FakeSession] = []
}

@MainActor
final class Rig {
    let suite = "nc-DisplaySound-test.\(UUID())"
    let defaults: UserDefaults
    let hub: NotchcastTapHub
    let controller: NotchcastController
    let log = SessionLog()

    init() async {
        defaults = UserDefaults(suiteName: suite)!
        hub = NotchcastTapHub(syntheticTag: tag, isTrusted: { true }, makeSession: { [log] in
            let session = FakeSession($0)
            log.all.append(session)
            return session
        })
        controller = NotchcastController(
            addons: [DisplaySoundAddon.self], defaults: defaults, hub: hub, dictation: FakeDictation(),
            presenter: FakePresenter())
        controller.start()
        await until("taps installed") { hub.subscriberCount == 2 }
        await until("display read") { self.module?.brightness.currentDisplays.count == 1 }
    }

    var module: DisplaySoundModule? {
        controller.context(forSwitch: DisplaySoundAddon.brightnessID)?.module(DisplaySoundModule.self)
    }
    var session: FakeSession { log.all.last(where: \.isRunning)! }

    func media(_ key: MediaLevelKey, down: Bool = true, repeat repeating: Bool = false,
               flags: NSEvent.ModifierFlags = [], synthetic: Bool = false) -> NotchcastTapRouter.Outcome {
        let data1 = key.rawValue << 16 | (down ? 0xA : 0xB) << 8 | (repeating ? 1 : 0)
        let event = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
                                       windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1)!.cgEvent!
        if synthetic { event.setIntegerValueField(.eventSourceUserData, value: tag) }
        return session.router.receive(type: CGEventType(rawValue: 14)!, event: event)
    }

    func key(_ code: Int, down: Bool = true) -> NotchcastTapRouter.Outcome {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: down)!
        event.flags = []
        return session.router.receive(type: down ? .keyDown : .keyUp, event: event)
    }

    func set(_ id: String, on: Bool) async {
        controller.preferences.set(id, on: on)
        try? await Task.sleep(for: .milliseconds(50))
    }

    func finish() {
        controller.stop()
        UserDefaults().removePersistentDomain(forName: suite)
    }
}

@MainActor
func until(_ message: String, _ condition: () -> Bool) async {
    for _ in 0..<300 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
    precondition(condition(), message)
}

@MainActor
func close(_ a: Double?, _ b: Double) -> Bool { a.map { abs($0 - b) < 1e-6 } == true }

@main
enum DisplaySoundModuleTests {
    @MainActor
    static func main() async {
        precondition(DisplaySoundAddon.switches.map(\.id) == ["displayBrightness", "volumeLevels"], "v1 ids")
        precondition(DisplaySoundAddon.switches.allSatisfy { $0.defaultEnabled && $0.category == .displaySound
            && $0.requiredGrants == [.accessibility] }, "both default on, Display & Sound, Accessibility")
        precondition(DisplaySoundAddon.settings.map(\.switchID) == ["displayBrightness"], "one settings row")

        let rig = await Rig()
        precondition(rig.session.mask & NotchcastTapPolicy.mask(for: .keyDown) != 0, "brightness tap takes F14/F15")

        precondition(rig.media(.volumeUp) == .swallow, "volume up is swallowed")
        await until("volume shown") { fake.levels.last?.source == "volume" }
        precondition(close(fake.levels.last?.value, 0.5625) && close(hw { $0.volume }, 0.5625), "1/16 volume step")
        for _ in 0..<4 { precondition(rig.media(.volumeUp, repeat: true) == .swallow, "owned repeat never passes") }
        precondition(rig.media(.volumeUp, down: false) == .swallow, "owned key-up swallowed")
        await until("repeats applied") { hw { $0.volume } > 0.6 }
        precondition(rig.media(.volumeUp, repeat: true) == .pass, "a repeat of a press we never took passes")

        let before = hw { $0.volume }
        precondition(rig.media(.volumeDown, flags: [.option, .shift]) == .swallow, "⌥⇧ is taken")
        _ = rig.media(.volumeDown, down: false)
        await until("fine step") { hw { $0.volume } < before }
        precondition(close(hw { $0.volume }, before - 1.0 / 64), "⌥⇧ is the 1/64 fine step")
        precondition(rig.media(.volumeDown, flags: [.command]) == .pass, "⌘ volume passes to the system")

        precondition(rig.media(.mute) == .swallow && rig.media(.mute, repeat: true) == .swallow, "mute once")
        _ = rig.media(.mute, down: false)
        await until("muted") { hw { $0.muted } == true }
        await until("muted shown") { fake.levels.last?.value == 0 }
        _ = rig.media(.volumeUp)
        _ = rig.media(.volumeUp, down: false)
        await until("raise unmutes") { hw { $0.muted } == false }

        hw { $0.muted = true; $0.refusesMute = true }
        let replayed = fake.replayed
        let levelCount = fake.levels.count
        _ = rig.media(.volumeUp)
        _ = rig.media(.volumeUp, down: false)
        await until("partial volume result shown") { fake.levels.count > levelCount }
        precondition(fake.replayed == replayed, "finding 6: failed unmute never replays the volume key")
        hw { $0.muted = false; $0.refusesMute = false }

        precondition(rig.media(.brightnessUp) == .swallow, "brightness up is swallowed")
        _ = rig.media(.brightnessUp, down: false)
        await until("brightness shown") { fake.levels.last?.source == "brightness" }
        let shown = fake.levels.last!
        precondition(close(shown.value, 0.5625) && shown.range == -0.25...1, "1/16 brightness, −0.25…1 range")
        precondition(close(hw { $0.system }, 0.5625), "backlight written")

        precondition(rig.key(107) == .swallow, "F14 on a non-Apple keyboard dims")
        precondition(rig.key(107, down: false) == .swallow)
        await until("F14 applied") { close(hw { $0.system }, 0.5) }

        fake.cursorOnDisplay = false
        _ = rig.media(.brightnessDown)
        _ = rig.media(.brightnessDown, down: false)
        await until("replayed") { fake.replayed == [.brightnessDown] }
        fake.cursorOnDisplay = true

        hw { $0.settable = false }
        _ = rig.media(.volumeUp)
        _ = rig.media(.volumeUp, down: false)
        await until("volume fallback replays") { fake.replayed == [.brightnessDown, .volumeUp] }
        hw { $0.settable = true }

        precondition(rig.media(.volumeUp, synthetic: true) == .pass, "our own replay is never caught")

        precondition(rig.media(.volumeDown) == .swallow)
        guard case .reenable(let ids) = rig.session.router.receive(type: .tapDisabledByTimeout, event: CGEvent(source: nil)!)
        else { preconditionFailure("a disable notice re-enables") }
        rig.session.router.reenabled(ids)
        await until("reset ran") { rig.media(.volumeDown, down: false) == .pass }

        await rig.set(DisplaySoundAddon.volumeID, on: false)
        await until("volume tap removed") { rig.hub.subscriberCount == 1 }
        precondition(rig.media(.volumeUp) == .pass, "volume off: the system's volume keys")
        precondition(rig.media(.brightnessUp) == .swallow, "brightness stays")
        _ = rig.media(.brightnessUp, down: false)
        await rig.set(DisplaySoundAddon.volumeID, on: true)
        await until("volume tap back") { rig.hub.subscriberCount == 2 }

        var held = hw { $0.volume }
        precondition(rig.media(.volumeUp) == .swallow, "volume up held")
        await until("held volume applied") { hw { $0.volume } > held }
        held = hw { $0.volume }
        await rig.set(DisplaySoundAddon.volumeID, on: false)
        _ = rig.media(.volumeUp, down: false)
        await rig.set(DisplaySoundAddon.volumeID, on: true)
        await until("volume tap back again") { rig.hub.subscriberCount == 2 }
        precondition(rig.media(.volumeUp) == .swallow)
        _ = rig.media(.volumeUp, down: false)
        await until("volume off mid-hold: the next press applies") { hw { $0.volume } > held }

        hw { $0.system = 0.5 }
        precondition(rig.media(.brightnessUp) == .swallow, "brightness up held")
        await until("held brightness applied") { hw { $0.system ?? 0 } > 0.5 }
        let lit = hw { $0.system ?? 0 }
        await rig.set(DisplaySoundAddon.brightnessID, on: false)
        _ = rig.media(.brightnessUp, down: false)
        await rig.set(DisplaySoundAddon.brightnessID, on: true)
        await until("brightness read again") { rig.module?.brightness.currentDisplays.count == 1 }
        precondition(rig.media(.brightnessUp) == .swallow)
        _ = rig.media(.brightnessUp, down: false)
        await until("brightness off mid-hold: the next press applies") { hw { $0.system ?? 0 } > lit }

        hw { $0.system = 0.0625 }
        for _ in 0..<2 {
            _ = rig.media(.brightnessDown)
            _ = rig.media(.brightnessDown, down: false)
        }
        await until("extra dimming") { hw { $0.gamma } != baseline }
        precondition(hw { $0.system } == 0, "extra dimming holds the backlight at 0")
        await rig.set(DisplaySoundAddon.brightnessID, on: false)
        await until("brightness off restores gamma") { hw { $0.gamma } == baseline }
        precondition(rig.hub.subscriberCount == 1, "brightness tap removed")

        fake.functionKeys = false
        await rig.set(DisplaySoundAddon.brightnessID, on: true)
        await until("brightness back") { rig.hub.subscriberCount == 2 }
        precondition(rig.key(107) == .pass, "F14 passes when the system's shortcut is off")
        precondition(rig.key(144) == .swallow, "144 is always brightness up")
        rig.finish()
        precondition(rig.hub.subscriberCount == 0, "stop removes every tap")
        await recoveryHandoff()
        print("nc-DisplaySound-module-test: PASS")
    }

    @MainActor
    static func recoveryHandoff() async {
        hw { $0 = Hardware() }
        let rig = await Rig()
        weak var module = rig.module
        _ = await rig.module?.brightness.set(-0.25, for: BrightnessDisplay.ID(rawValue: 9, uuid: "display-9"))
        precondition(hw { $0.gamma } != baseline, "finding 1: dim before unplug")
        hw { $0.online = false }
        let watches = fake.displayWatchCount
        await rig.set(DisplaySoundAddon.brightnessID, on: false)
        await until("finding 1: recovery owns pending restore after teardown") {
            fake.displayWatchCount > watches
        }
        await rig.set(DisplaySoundAddon.volumeID, on: false)
        precondition(module == nil, "finding 1: the switch module is detached")
        hw { $0.online = true }
        fake.displayChanged?(false)
        await until("finding 1: recovery restores after module teardown") { hw { $0.gamma } == baseline }
        rig.finish()
        print("finding 1 recovery handoff: PASS")
    }
}
