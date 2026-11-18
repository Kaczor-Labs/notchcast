// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/NotchcastMediaKey.swift
// notchcast-sources: Tinycast/Features/Notchcast/DisplaySound/Model/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandLevelDwell.swift
// notchcast-sources: Tinycast/Features/Notchcast/DisplaySound/Service/DisplaySoundSystem.swift
// notchcast-sources: Tinycast/Features/Notchcast/DisplaySound/Service/BrightnessDDCChannel.swift
// notchcast-sources: Tinycast/Features/Notchcast/DisplaySound/Service/BrightnessDisplayService.swift
// notchcast-sources: Tinycast/Features/Notchcast/DisplaySound/Service/BrightnessController.swift
// notchcast-sources: Tinycast/Features/Notchcast/DisplaySound/Service/DisplaySoundRecovery.swift
// notchcast-sources: Tinycast/Features/Notchcast/DisplaySound/Service/DisplaySpeakerController.swift

import CoreGraphics
import Foundation
import Synchronization

@MainActor
protocol NotchcastModule: AnyObject {
    func start()
    func stop()
}

func check(_ condition: Bool, _ message: String) {
    guard condition else { fatalError("nc-DisplaySound-speaker-test: \(message)") }
}

/// A monitor's VCP registers; a code missing from `values` never replies.
struct Monitor {
    var uuid: String
    var name: String
    var builtIn = false
    var online = true
    var system: Double?
    var ddc = true
    var values: [UInt8: (current: UInt16, maximum: UInt16)] = [0x10: (50, 100), 0x62: (50, 100), 0x8D: (2, 2)]
    var gamma = BrightnessGamma(red: [0, 1], green: [0, 1], blue: [0, 1])
    var takesGamma = true
}

struct Rack {
    var monitors: [UInt32: Monitor] = [:]
    var output: UInt32? = 1
    var outputName: String? = "DELL U2720Q"
    var sent: [[UInt8]] = []
    var requested: [UInt8] = []
    var asked: UInt8?
}

let rack = Mutex(Rack())
func hw<T: Sendable>(_ body: (inout Rack) -> T) -> T { rack.withLock { body(&$0) } }
let baseline = BrightnessGamma(red: [0, 1], green: [0, 1], blue: [0, 1])

func link(_ raw: UInt32) -> BrightnessDDCLink {
    BrightnessDDCLink(
        send: { packet in
            hw { rack in
                rack.sent.append(packet)
                if packet[0] == 0x82 {
                    rack.requested.append(packet[2])
                    rack.asked = packet[2]
                } else if let maximum = rack.monitors[raw]?.values[packet[2]]?.maximum {
                    rack.monitors[raw]?.values[packet[2]] = (UInt16(packet[3]) << 8 | UInt16(packet[4]), maximum)
                }
                return true
            }
        },
        receive: { _ in
            hw { rack in
                guard let code = rack.asked, let value = rack.monitors[raw]?.values[code] else { return nil }
                var reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, code, 0x00, UInt8(value.maximum >> 8),
                                      UInt8(value.maximum & 0xFF), UInt8(value.current >> 8), UInt8(value.current & 0xFF)]
                reply.append(reply.reduce(UInt8(0x50), ^))
                return reply
            }
        })
}

@MainActor
final class Watchers {
    var displays: [@MainActor @Sendable (Bool) -> Void] = []
    var sleep: [@MainActor @Sendable () -> Void] = []
}

@MainActor let watchers = Watchers()

let system = DisplaySoundSystem(
    displays: .init(
        online: { hw { rack in rack.monitors.keys.sorted().filter { rack.monitors[$0]?.online == true } } },
        uuid: { raw in hw { $0.monitors[raw]?.uuid } },
        isActive: { raw in hw { $0.monitors[raw]?.online == true } },
        isBuiltIn: { raw in hw { $0.monitors[raw]?.builtIn == true } },
        readSystem: { raw in hw { $0.monitors[raw]?.system } },
        writeSystem: { raw, value in hw { $0.monitors[raw]?.system = value; return true } },
        discoverDDC: {
            hw { rack in
                var links: [String: BrightnessDDCLink] = [:]
                for (raw, monitor) in rack.monitors where monitor.ddc && monitor.online {
                    links[monitor.uuid.uppercased()] = link(raw)
                }
                return links
            }
        },
        readGamma: { raw in hw { $0.monitors[raw]?.gamma } },
        writeGamma: { raw, gamma in
            hw { rack in
                guard rack.monitors[raw]?.takesGamma == true else { return false }
                rack.monitors[raw]?.gamma = gamma
                return true
            }
        }),
    audio: .init(
        defaultOutput: { hw { $0.output } }, has: { _, _ in false }, stereoChannels: { _ in nil },
        volume: { _, _ in nil }, canSetVolume: { _, _ in false }, setVolume: { _, _, _ in false },
        muted: { _ in nil }, canSetMute: { _ in false }, setMuted: { _, _ in false },
        displayAudioName: { _ in hw { $0.outputName } }),
    sleep: { _ in },
    screenNames: { hw { $0.monitors.mapValues(\.name) } },
    displayContaining: { _, ids in ids.first },
    functionKeysAdjustBrightness: { true },
    replay: { _, _ in },
    watchDisplays: { handler in
        watchers.displays.append(handler)
        return [NSObject()]
    },
    watchSleep: { handler in
        watchers.sleep.append(handler)
        return [NSObject()]
    },
    watchAudio: { _, _ in [] })

func install(_ monitors: [UInt32: Monitor]) { hw { $0 = Rack(); $0.monitors = monitors } }
func value(_ raw: UInt32, _ code: UInt8) -> UInt16? { hw { $0.monitors[raw]?.values[code]?.current } }
func id(_ raw: UInt32) -> BrightnessDisplay.ID { BrightnessDisplay.ID(rawValue: raw, uuid: "uuid-\(raw)") }

/// Lets the main actor's queued tasks run; no clock is read.
@MainActor
func settle(_ message: String, _ condition: () -> Bool) async {
    for _ in 0..<10_000 where !condition() { await Task.yield() }
    check(condition(), message)
}

@main
enum DisplaySoundSpeakerTests {
    static func main() async {
        await extraDimming()
        await sleepReset()
        await speakers()
        await silentMonitors()
        await reconnection()
        print("nc-DisplaySound-speaker-test: PASS")
    }

    static func extraDimming() async {
        install([1: Monitor(uuid: "uuid-1", name: "Built-in", builtIn: true, system: 0.5)])
        let service = BrightnessDisplayService(displays: system.displays)
        _ = await service.perform(.refresh(names: [:]))
        _ = await service.perform(.set(-0.2, id(1)))
        check(hw { $0.monitors[1]?.gamma } != baseline, "dimmed below the backlight")
        let off = await service.perform(.extraDimming(false))!
        check(off.displays[0].level == BrightnessLevel(0, extraDimming: false), "off lifts it to the backlight minimum")
        check(hw { $0.monitors[1]?.gamma } == baseline, "off gives the curve back bit for bit")
        let down = await service.perform(.step(up: false, fine: false, id(1)))!
        check(down.displays[0].level.value == 0 && hw { $0.monitors[1]?.gamma } == baseline, "off: keys stop at 0")
        check(down.displays[0].level.range == 0...1, "off: the HUD's bar has no dimming zone")
        _ = await service.perform(.refresh(names: [:]))
        let kept = await service.perform(.step(up: false, fine: false, id(1)))!
        check(kept.displays[0].level.value == 0, "a refresh keeps the setting")
        _ = await service.perform(.extraDimming(true))
        let on = await service.perform(.step(up: false, fine: false, id(1)))!
        check(on.displays[0].level.value == -0.0625 && on.displays[0].level.range == -0.25...1, "on: dimming is back")
        check(await service.restoreAll(), "restored")
    }

    @MainActor
    static func sleepReset() async {
        install([
            1: Monitor(uuid: "uuid-1", name: "Built-in", builtIn: true, system: 0.5),
            2: Monitor(uuid: "uuid-2", name: "Plain", ddc: false),
            3: Monitor(uuid: "uuid-3", name: "Stubborn", ddc: false),
        ])
        let service = BrightnessDisplayService(displays: system.displays)
        _ = await service.perform(.refresh(names: [:]))
        _ = await service.perform(.set(-0.25, id(1)))
        _ = await service.perform(.set(0.4, id(2)))
        _ = await service.perform(.set(0.4, id(3)))
        hw { $0.monitors[3]?.takesGamma = false }
        let slept = await service.perform(.sleep)!
        check(slept.displays.map(\.level.value) == [0, 0.4, 0.4], "sleep drops extra dimming, software stays")
        check(hw { $0.monitors[1]?.gamma == baseline && $0.monitors[2]?.gamma == baseline },
              "sleep gives every curve back")
        let profile = BrightnessGamma(red: [0, 0.9], green: [0, 0.9], blue: [0, 0.9])
        hw { $0.monitors[2]?.gamma = profile; $0.monitors[3]?.takesGamma = true; $0.monitors[3]?.gamma = profile }
        let woke = await service.perform(.refresh(names: [:]))!
        check(woke.displays[0].level == BrightnessLevel(0) && hw { $0.monitors[1]?.gamma == baseline },
              "the backlight wakes undimmed")
        check(woke.displays[1].level.value == 0.4 && hw { $0.monitors[2]?.gamma != profile },
              "software dimming comes back over a curve macOS reset")
        check(hw { $0.monitors[3]?.gamma == baseline.scaled(BrightnessLevel(0.4, softwareOnly: true).picture) },
              "a curve that refused at sleep scales the baseline it kept")
        _ = await service.perform(.step(up: false, fine: false, id(1)))
        check(hw { $0.monitors[1]?.gamma != baseline }, "after a wake the keys still dim")

        install([4: Monitor(uuid: "uuid-4", name: "Built-in", builtIn: true, system: 0.5)])
        let controller = BrightnessController(system: system)
        watchers.sleep = []
        controller.start()
        await settle("first refresh") { controller.currentDisplays.count == 1 }
        _ = await controller.set(-0.25, for: id(4))
        for handler in watchers.sleep { handler() }
        await settle("the sleep notification resets") { controller.level(of: id(4))?.value == 0 }
        check(hw { $0.monitors[4]?.gamma == baseline }, "the controller restores on sleep")
        controller.allowExtraDimming(false)
        await settle("the switch reaches the service") { controller.level(of: id(4))?.extraDimming == false }
        controller.stop()
    }

    @MainActor
    static func speakers() async {
        install([
            1: Monitor(uuid: "uuid-1", name: "Built-in", builtIn: true, system: 0.5),
            2: Monitor(uuid: "uuid-2", name: "DELL U2720Q"),
            3: Monitor(uuid: "uuid-3", name: "LG HDR 4K"),
        ])
        let suite = "nc-DisplaySound-speaker-test.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = BrightnessDisplayService(displays: system.displays)
        let speakers = DisplaySpeakerController(system: system, service: service, defaults: defaults)
        check(await speakers.apply(.toggleMute) == nil, "stopped: macOS keeps the key")
        speakers.start()

        let up = await speakers.apply(.step(increasing: true, fine: false))
        check(up == DisplaySpeakerLevel(volume: 0.56, muted: false), "volume up on the named monitor: \(String(describing: up))")
        check(value(2, 0x62) == 56 && value(3, 0x62) == 50, "only the DELL's VCP 0x62 moved")
        let muted = await speakers.apply(.toggleMute)
        check(muted == DisplaySpeakerLevel(volume: 0.56, muted: true) && value(2, 0x8D) == 1, "mute writes 0x8D = 1")
        let unmuted = await speakers.apply(.step(increasing: true, fine: true))
        check(unmuted?.muted == false && value(2, 0x8D) == 2 && value(2, 0x62) == 58, "volume up unmutes, 1/64 step")

        let stored = DisplaySpeakerStore(data: defaults.data(forKey: DisplaySpeakerController.storeKey))
        check(stored.levels == ["UUID-2": DisplaySpeakerLevel(volume: 0.58, muted: false)], "remembered per display")

        hw { $0.outputName = nil }
        check(await speakers.apply(.step(increasing: true, fine: false)) == nil, "not a display's audio: macOS")
        hw { $0.outputName = "HDMI" }
        check(await speakers.apply(.step(increasing: true, fine: false)) == nil, "two monitors, no name: macOS")
        hw { $0.outputName = "DELL U2720Q"; $0.monitors[2]?.values[0x8D] = nil }
        check(await speakers.apply(.toggleMute) == nil, "no mute control: macOS mutes")
        check(await speakers.apply(.step(increasing: false, fine: false)) != nil, "its volume still works")
        speakers.stop()
        check(await speakers.apply(.step(increasing: true, fine: false)) == nil, "stopped again: macOS")
    }

    @MainActor
    static func silentMonitors() async {
        install([5: Monitor(uuid: "uuid-5", name: "Quiet", values: [0x10: (50, 100)])])
        hw { $0.outputName = "Quiet" }
        let suite = "nc-DisplaySound-speaker-test.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        watchers.displays = []
        let speakers = DisplaySpeakerController(system: system, service: BrightnessDisplayService(displays: system.displays),
                                                defaults: defaults)
        speakers.start()
        check(await speakers.apply(.step(increasing: true, fine: false)) == nil, "no volume reply: macOS")
        check(hw { $0.requested } == [0x62, 0x62, 0x62], "asked three times")
        hw { $0.requested = [] }
        check(await speakers.apply(.step(increasing: true, fine: false)) == nil, "still macOS")
        check(hw { $0.requested }.isEmpty, "a silent monitor is not asked again on every key")
        for handler in watchers.displays { handler(false) }
        _ = await speakers.apply(.step(increasing: true, fine: false))
        check(hw { $0.requested.count } == 3, "a display change asks again")
        speakers.stop()
    }

    @MainActor
    static func reconnection() async {
        install([6: Monitor(uuid: "uuid-6", name: "Desk"), 7: Monitor(uuid: "uuid-7", name: "Side")])
        hw { $0.outputName = "Desk" }
        let suite = "nc-DisplaySound-speaker-test.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = BrightnessDisplayService(displays: system.displays)
        let first = DisplaySpeakerController(system: system, service: service, defaults: defaults)
        first.start()
        _ = await first.apply(.step(increasing: false, fine: false))
        _ = await first.apply(.toggleMute)
        first.stop()

        watchers.displays = []
        let speakers = DisplaySpeakerController(system: system, service: service, defaults: defaults)
        speakers.start()
        hw { $0.monitors[6]?.online = false; $0.monitors[7]?.online = false }
        for handler in watchers.displays { handler(false) }
        check(speakers.restoring == nil, "a display leaving restores nothing")
        hw { rack in
            rack.monitors[6]?.online = true
            rack.monitors[7]?.online = true
            rack.monitors[6]?.values[0x62] = (90, 100)
            rack.monitors[6]?.values[0x8D] = (2, 2)
            rack.sent = []
        }
        for handler in watchers.displays { handler(false) }
        await speakers.restoring?.value
        check(value(6, 0x62) == 44 && value(6, 0x8D) == 1, "the remembered level and mute come back on reconnect")
        check(hw { $0.sent.allSatisfy { $0 != DisplayDDC.write(.volume, 50) } } && value(7, 0x62) == 50,
              "a display with no remembered level is left alone")
        speakers.stop()
    }
}
