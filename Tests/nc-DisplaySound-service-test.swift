// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/NotchcastMediaKey.swift
// notchcast-sources: Tinycast/Features/Notchcast/DisplaySound/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/DisplaySound/Service/DisplaySoundSystem.swift
// notchcast-sources: Tinycast/Features/Notchcast/DisplaySound/Service/BrightnessDDCChannel.swift
// notchcast-sources: Tinycast/Features/Notchcast/DisplaySound/Service/BrightnessDisplayService.swift
// notchcast-sources: Tinycast/Features/Notchcast/DisplaySound/Service/BrightnessController.swift
// notchcast-sources: Tinycast/Features/Notchcast/DisplaySound/Service/DisplaySoundRecovery.swift
// notchcast-sources: Tinycast/Features/Notchcast/DisplaySound/Service/AudioLevelAccess.swift
// notchcast-sources: Tinycast/Features/Notchcast/DisplaySound/Service/AudioLevelsService.swift

import CoreGraphics
import Foundation
import Synchronization

@MainActor
protocol NotchcastModule: AnyObject {
    func start()
    func stop()
}

func check(_ condition: Bool, _ message: String) {
    guard condition else { fatalError("nc-DisplaySound-service-test: \(message)") }
}

struct FakeDisplay {
    var uuid: String
    var active = true
    var builtIn = false
    var system: Double?
    var gamma = BrightnessGamma(red: [0, 0.5, 1], green: [0, 0.5, 1], blue: [0, 0.5, 1])
    var ddc = false
    var accepts = true
    var replies = true
    var ddcValue: UInt16 = 50
    var ddcMax: UInt16 = 100
    var takesGamma = true
}

struct Hardware {
    var displays: [UInt32: FakeDisplay] = [:]
    var order: [UInt32] = []
    var gammaWrites: [UInt32] = []
    var requests = 0
    var ddcWrites: [UInt16] = []
    var slept: [Duration] = []
    var device: UInt32? = 1
    var controls: Set<AudioVolumeControl> = [.virtualMain]
    var channels: [UInt32: Double] = [:]
    var volume = 0.5
    var muted: Bool? = false
    var settable = true
    var roundsTo: Double?
    var refusesMute = false
    var watched: [UInt32?] = []
}

let rack = Mutex(Hardware())

final class DiscoveryGate: Sendable {
    struct State {
        var armed = false
        var entered = false
        var released = false
        var finished = false
        var onEnter: (@Sendable () -> Void)?
    }
    let state = Mutex(State())

    func wait() {
        guard state.withLock({ $0.armed }) else { return }
        let notify = state.withLock { state in
            state.entered = true
            defer { state.onEnter = nil }
            return state.onEnter
        }
        notify?()
        let deadline = Date().addingTimeInterval(2)
        while !state.withLock({ $0.released }), Date() < deadline { Thread.sleep(forTimeInterval: 0.001) }
        state.withLock { $0.finished = true }
    }
}

let discovery = DiscoveryGate()
let gammaRead = DiscoveryGate()

func hw<T: Sendable>(_ body: (inout Hardware) -> T) -> T { rack.withLock { body(&$0) } }

func link(_ raw: UInt32) -> BrightnessDDCLink {
    BrightnessDDCLink(
        send: { packet in
            hw { state in
                guard state.displays[raw]?.accepts == true else { return false }
                if packet == BrightnessDDC.request() { state.requests += 1 } else {
                    let value = UInt16(packet[3]) << 8 | UInt16(packet[4])
                    state.ddcWrites.append(value)
                    state.displays[raw]?.ddcValue = value
                }
                return true
            }
        },
        receive: { _ in
            hw { state in
                guard let display = state.displays[raw], display.replies else { return nil }
                var reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, UInt8(display.ddcMax >> 8),
                                      UInt8(display.ddcMax & 0xFF), 0x00, UInt8(display.ddcValue)]
                reply.append(reply.reduce(UInt8(0x50), ^))
                return reply
            }
        })
}

nonisolated(unsafe) var watcher: (@MainActor @Sendable (Bool) -> Void)?

let system = DisplaySoundSystem(
    displays: .init(
        online: { hw { $0.order } },
        uuid: { raw in hw { $0.displays[raw]?.uuid } },
        isActive: { raw in hw { $0.displays[raw]?.active == true } },
        isBuiltIn: { raw in hw { $0.displays[raw]?.builtIn == true } },
        readSystem: { raw in hw { $0.displays[raw]?.system } },
        writeSystem: { raw, value in
            hw { state in
                guard state.displays[raw]?.system != nil else { return false }
                state.displays[raw]?.system = value
                return true
            }
        },
        discoverDDC: {
            discovery.wait()
            return hw { state in
                var links: [String: BrightnessDDCLink] = [:]
                for (raw, display) in state.displays where display.ddc { links[display.uuid.uppercased()] = link(raw) }
                return links
            }
        },
        readGamma: { raw in
            gammaRead.wait()
            return hw { $0.displays[raw]?.gamma }
        },
        writeGamma: { raw, gamma in
            hw { state in
                guard state.displays[raw]?.takesGamma == true else { return false }
                state.displays[raw]?.gamma = gamma
                state.gammaWrites.append(raw)
                return true
            }
        }),
    audio: .init(
        defaultOutput: { hw { $0.device } },
        has: { _, control in hw { $0.controls.contains(control) } },
        stereoChannels: { _ in [1, 2] },
        volume: { _, control in
            hw { state in
                if case let .channel(number) = control { return state.channels[number] }
                return state.volume
            }
        },
        canSetVolume: { _, _ in hw { $0.settable } },
        setVolume: { _, control, value in
            hw { state in
                let stored = state.roundsTo ?? value
                if case let .channel(number) = control { state.channels[number] = stored } else { state.volume = stored }
                return true
            }
        },
        muted: { _ in hw { $0.muted } },
        canSetMute: { _ in hw { $0.muted != nil } },
        setMuted: { _, value in hw {
            guard !$0.refusesMute else { return false }
            $0.muted = value
            return true
        } }),
    sleep: { duration in
        hw { $0.slept.append(duration) }
        try await Task.sleep(for: duration / 100)
    },
    screenNames: { [:] },
    displayContaining: { _, ids in ids.first },
    functionKeysAdjustBrightness: { true },
    replay: { _, _ in },
    watchDisplays: { handler in
        watcher = handler
        return [NSObject()]
    },
    watchAudio: { output, _ in
        hw { $0.watched.append(output) }
        return [NSObject()]
    })

let baseline = BrightnessGamma(red: [0, 0.5, 1], green: [0, 0.5, 1], blue: [0, 0.5, 1])

func install(_ displays: [UInt32: FakeDisplay]) {
    hw { state in
        state = Hardware()
        state.displays = displays
        state.order = displays.keys.sorted()
    }
}

func id(_ raw: UInt32) -> BrightnessDisplay.ID { BrightnessDisplay.ID(rawValue: raw, uuid: "uuid-\(raw)") }

@MainActor
func until(_ message: String, _ condition: () -> Bool) async {
    for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
    check(condition(), message)
}

@main
enum DisplaySoundServiceTests {
    static func main() async {
        await brightness()
        await recovery()
        await learnedScale()
        await stranded()
        await controller()
        await gammaOwnership()
        await freshDDCStep()
        await nonblockingStop()
        await audio()
        await quitRestore()
        await contendedQuit()
        await quitDuringGammaRead()
        await audioRebind()
        if ProcessInfo.processInfo.environment["DISPLAY_SOUND_MUTANT"] == nil {
            mutations()
            print("SKIP: no hardware tests; findings 1-10 baseline PASS; planted breaks FAIL as expected; originals PASS")
        }
        print("nc-DisplaySound-service-test: PASS")
    }

    static func brightness() async {
        install([
            1: FakeDisplay(uuid: "uuid-1", builtIn: true, system: 0.5),
            2: FakeDisplay(uuid: "uuid-2"),
        ])
        let service = BrightnessDisplayService(displays: system.displays)
        let first = await service.perform(.refresh(names: [:]))!
        check(first.displays.map(\.control) == [.system, .software], "built-in system, external software")
        check(hw { $0.gammaWrites.isEmpty }, "an undimmed refresh writes no gamma")

        _ = await service.perform(.set(-0.25, id(1)))
        _ = await service.perform(.set(0.5, id(2)))
        check(hw { $0.displays[1]?.system == 0 }, "extra dimming puts the backlight at 0")
        check(hw { $0.displays[1]?.gamma == baseline.scaled(BrightnessLevel.minimumPicture) }, "built-in dimmed")
        let external = hw { $0.displays[2]!.gamma }
        hw { $0.gammaWrites = [] }

        let undim = await service.perform(.set(0.25, id(1)))!
        check(undim.displays[0].level.value == 0.25, "un-dimmed to 0.25")
        check(hw { $0.displays[1]?.gamma == baseline }, "un-dim restores this display's baseline exactly")
        check(hw { $0.gammaWrites == [1] && $0.displays[2]?.gamma == external }, "other displays' gamma untouched")

        let stepped = await service.perform(.step(up: false, fine: true, id(1)))!
        check(abs(stepped.displays[0].level.value - (0.25 - 1.0 / 64)) < 1e-9, "1/64 fine step")
        check(await service.perform(.set(.nan, id(1))) == nil, "NaN is refused")

        hw { $0.displays[1]?.active = false }
        check(await service.perform(.set(0.9, id(1))) == nil, "an asleep display is not written")
        hw { $0.displays[1]?.active = true }

        check(await service.restoreAll(), "nothing owed once every display took its curve back")
        check(hw { $0.displays[2]?.gamma == baseline }, "stop restores every dimmed curve")
    }

    static func recovery() async {
        install([3: FakeDisplay(uuid: "uuid-3", ddc: true, ddcValue: 40)])
        let service = BrightnessDisplayService(displays: system.displays)
        var snapshot = await service.perform(.refresh(names: [:]))!
        check(snapshot.displays[0].control == .ddc && snapshot.displays[0].level.value == 0.4, "DDC read")
        check(snapshot.retrying.isEmpty, "a live monitor is not retried")

        _ = await service.perform(.set(-0.25, id(3)))
        check(hw { $0.ddcWrites.last == 0 }, "deep dim writes DDC 0")
        hw { $0.order = [] }
        _ = await service.perform(.refresh(names: [:]))
        hw { $0.order = [3] }
        snapshot = await service.perform(.refresh(names: [:]))!
        check(snapshot.displays[0].level.picture >= BrightnessRecoveryPolicy.reconnectionDimFloor - 1e-9,
              "reconnected deep dim is lifted to the floor")
        check(hw { $0.displays[3]?.gamma == baseline.scaled(BrightnessRecoveryPolicy.reconnectionDimFloor) },
              "the floor scales the kept baseline, not the curve found on return")

        hw { $0.displays[3]?.replies = false; $0.requests = 0 }
        snapshot = await service.perform(.refresh(names: [:]))!
        check(snapshot.displays[0].control == .writeOnlyDDC, "silent monitor is write-only")
        check(snapshot.retrying == ["UUID-3"], "a monitor that replied before is retried")
        check(hw { $0.requests == 3 }, "probed three times")
        snapshot = await service.perform(.refresh(names: [:]))!
        check(snapshot.displays[0].control == .writeOnlyDDC && hw { $0.requests == 3 }, "write-only is remembered")
        check(await service.perform(.set(0.7, id(3)))?.displays[0].level.value == 0.7, "write-only still writes")
        check(hw { $0.ddcWrites.last == 70 }, "written on the 0…100 scale it reported")

        hw { $0.displays[3]?.replies = true; $0.displays[3]?.ddcValue = 20 }
        let stale = snapshot.serial
        check(await service.perform(.retry(uuid: "UUID-3", since: stale)) == nil, "a retry older than a write is dropped")
        let current = await service.perform(.refresh(names: [:]))!.serial
        let retried = await service.perform(.retry(uuid: "UUID-3", since: current))!
        check(retried.displays[0].control == .ddc && retried.displays[0].level.value == 0.2, "a fresh retry applies")
        await service.restoreAll()

        install([4: FakeDisplay(uuid: "uuid-4", ddc: true, replies: false)])
        let fresh = BrightnessDisplayService(displays: system.displays)
        snapshot = await fresh.perform(.refresh(names: [:]))!
        check(snapshot.displays[0].control == .writeOnlyDDC && snapshot.retrying.isEmpty, "never replied: no retry")
        check(await fresh.perform(.set(0.7, id(4))) != nil && hw { $0.ddcWrites.last == 70 },
              "never replied: the assumed 0…100 scale")
        hw { $0.displays[4]?.accepts = false }
        let dead = BrightnessDisplayService(displays: system.displays)
        check(await dead.perform(.refresh(names: [:]))!.displays[0].control == .software, "dead DDC dims in software")
    }

    static func learnedScale() async {
        install([10: FakeDisplay(uuid: "uuid-10", ddc: true, ddcValue: 51, ddcMax: 255)])
        let service = BrightnessDisplayService(displays: system.displays)
        let live = await service.perform(.refresh(names: [:]))!
        check(live.displays[0].control == .ddc && live.displays[0].level.value == 0.2, "read on its 0…255 scale")
        hw { $0.displays[10]?.replies = false }
        let silent = await service.perform(.refresh(names: [:]))!
        check(silent.displays[0].control == .writeOnlyDDC, "silent on the next refresh")
        _ = await service.perform(.set(0.5, id(10)))
        check(hw { $0.ddcWrites.last == 128 }, "a silent refresh keeps the learned 0…255 scale")
        await service.restoreAll()
        _ = await service.perform(.refresh(names: [:]))
        _ = await service.perform(.set(0.2, id(10)))
        check(hw { $0.ddcWrites.last == 51 }, "the learned scale outlives a stop")
    }

    static func stranded() async {
        install([6: FakeDisplay(uuid: "uuid-6"), 7: FakeDisplay(uuid: "uuid-7")])
        let service = BrightnessDisplayService(displays: system.displays)
        _ = await service.perform(.refresh(names: [:]))
        _ = await service.perform(.set(0.5, id(6)))
        _ = await service.perform(.set(0.5, id(7)))
        let dimmed = baseline.scaled(BrightnessLevel(0.5, softwareOnly: true).picture)
        check(hw { $0.displays[6]?.gamma == dimmed && $0.displays[7]?.gamma == dimmed }, "both dimmed")

        hw { $0.order = [7] }
        _ = await service.perform(.refresh(names: [:]))
        hw { $0.displays[7]?.takesGamma = false; $0.gammaWrites = [] }
        check(!(await service.restoreAll()), "an absent display and a refused write stay owed")
        check(hw { $0.gammaWrites.isEmpty && $0.displays[7]?.gamma == dimmed }, "nothing written yet")

        hw { $0.order = [6, 7]; $0.displays[7]?.takesGamma = true }
        check(await service.restoreAll(), "both owed curves restored on return")
        check(hw { $0.displays[6]?.gamma == baseline && $0.displays[7]?.gamma == baseline },
              "the kept baselines, not the dimmed curves found on return")
    }

    @MainActor
    static func controller() async {
        install([5: FakeDisplay(uuid: "uuid-5", ddc: true, ddcValue: 60)])
        let controller = BrightnessController(system: system)
        controller.start()
        await until("first refresh") { controller.currentDisplays.count == 1 }

        hw { $0.slept = [] }
        watcher?(true)
        watcher?(false)
        await until("wake refresh") { hw { $0.slept.count } == 1 }
        try? await Task.sleep(for: .milliseconds(80))
        check(hw { $0.slept } == [BrightnessRecoveryPolicy.wakeSettle], "3 s wake settle, not cut short")

        hw { $0.displays[5]?.replies = false; $0.slept = []; $0.requests = 0 }
        watcher?(false)
        await until("retries") { hw { $0.slept.count } == 4 }
        await until("retries done") { hw { $0.requests } == 3 + 3 * 3 }
        check(hw { $0.slept } == [BrightnessRecoveryPolicy.screenSettle] + BrightnessRecoveryPolicy.retryDelays,
              "DDC retries at 2/5/15 s")

        let result = await controller.step(up: true, fine: false, for: id(5))
        check(result == .applied(BrightnessLevel(0.625)), "1/16 step: \(result)")
        _ = await controller.set(-0.25, for: id(5))
        check(hw { $0.displays[5]?.gamma != baseline }, "dimmed")
        controller.stop()
        check(controller.currentDisplays.isEmpty, "stop forgets")
        await until("stop restores asynchronously") { hw { $0.displays[5]?.gamma == baseline } }
        check(await controller.step(up: true, fine: false, for: id(5)) == .cancelled, "stopped: nothing applied")

        install([8: FakeDisplay(uuid: "uuid-8")])
        let away = BrightnessController(system: system)
        away.start()
        await until("software display read") { away.currentDisplays.count == 1 }
        _ = await away.set(0.5, for: id(8))
        hw { $0.order = [] }
        watcher = nil
        away.stop()
        check(hw { $0.displays[8]?.gamma != baseline }, "an absent display is not written")
        await until("recovery watcher installed") { watcher != nil }
        hw { $0.order = [8] }
        watcher?(false)
        await until("stopped: a returning display gets its curve back") { hw { $0.displays[8]?.gamma == baseline } }
    }

    static func gammaOwnership() async {
        for restore in [false, true] {
            install([12: FakeDisplay(uuid: "uuid-12")])
            let service = BrightnessDisplayService(displays: system.displays)
            _ = await service.perform(.refresh(names: [:]))
            _ = await service.perform(.set(0.5, id(12)))
            let foreign = baseline.scaled(0.8)
            hw { $0.displays[12]?.gamma = foreign; $0.gammaWrites = [] }
            if restore {
                check(await service.restoreAll(), "foreign gamma relinquishes restore debt")
            } else {
                check(await service.perform(.set(0.25, id(12))) == nil, "foreign gamma refuses further dimming")
                check(await service.perform(.set(0.1, id(12))) == nil, "foreign gamma stays unowned")
            }
            check(hw { $0.displays[12]?.gamma == foreign && $0.gammaWrites.isEmpty },
                  "finding 2: another writer's curve is never overwritten")
        }
        print("finding 2 gamma ownership: PASS")
    }

    static func freshDDCStep() async {
        install([13: FakeDisplay(uuid: "uuid-13", ddc: true)])
        let service = BrightnessDisplayService(displays: system.displays)
        _ = await service.perform(.refresh(names: [:]))
        hw { $0.displays[13]?.ddcValue = 80 }
        let stepped = await service.perform(.step(up: true, fine: false, id(13)))
        check(stepped?.displays.first?.level.value == 0.8125 && hw { $0.ddcWrites.last == 81 },
              "finding 5: a step reads the monitor's physical-button change")
        hw { $0.displays[13]?.replies = false; $0.ddcWrites = [] }
        check(await service.perform(.step(up: true, fine: false, id(13))) == nil,
              "a responsive monitor that stops answering does not use a stale reading")
        check(hw { $0.ddcWrites.isEmpty }, "no stale DDC write")
        print("finding 5 fresh DDC step: PASS")
    }

    @MainActor
    static func nonblockingStop() async {
        install([14: FakeDisplay(uuid: "uuid-14", ddc: true)])
        let recovery = DisplaySoundRecovery(system: system)
        let controller = BrightnessController(system: system, recovery: recovery)
        controller.start()
        await until("blocked-stop initial read") { controller.currentDisplays.count == 1 }
        _ = await controller.set(-0.25, for: id(14))
        var refresh: Task<Void, Never>?
        let stopped: (Bool, Bool) = await withCheckedContinuation { continuation in
            discovery.state.withLock {
                $0 = DiscoveryGate.State(armed: true, onEnter: {
                    DispatchQueue.main.async {
                        let entered = !discovery.state.withLock { $0.finished }
                        controller.stop()
                        let returned = !discovery.state.withLock { $0.finished }
                        discovery.state.withLock { $0.released = true }
                        continuation.resume(returning: (entered, returned))
                    }
                })
            }
            refresh = Task { await controller.refresh() }
        }
        check(stopped.0, "DDC gate remains held before stop")
        check(stopped.1, "finding 3: stop returns while DDC remains blocked")
        await refresh?.value
        await until("serialized restore after DDC") { hw { $0.displays[14]?.gamma == baseline } }
        discovery.state.withLock { $0 = DiscoveryGate.State() }
        recovery.stop()
        print("finding 3 nonblocking serialized restore: PASS")
    }

    @MainActor
    static func audio() async {
        install([:])
        let service = AudioLevelsService(system: system)
        service.start()

        hw { $0.volume = 0.5; $0.muted = true }
        var result = await service.apply(.step(increasing: true, fine: false))
        check(result == .applied(AudioOutput(device: 1, volume: 0.5625, muted: false)), "raising unmutes: \(result)")
        hw { $0.volume = 0.5; $0.muted = true; $0.refusesMute = true }
        result = await service.apply(.step(increasing: true, fine: false))
        check(result == .partiallyApplied(AudioOutput(device: 1, volume: 0.5625, muted: true)),
              "finding 6: a failed unmute after a volume write must not replay the volume key")
        check(hw { $0.volume == 0.5625 && $0.muted == true }, "one volume step when unmute fails")
        hw { $0.refusesMute = false; $0.muted = false }
        print("finding 6 partial audio write: PASS")
        result = await service.apply(.step(increasing: false, fine: false))
        check(hw { $0.muted } == false, "lowering keeps it unmuted")
        result = await service.apply(.step(increasing: true, fine: true))
        check(result == .applied(AudioOutput(device: 1, volume: 0.5 + 1.0 / 64, muted: false)), "1/64 fine: \(result)")
        result = await service.apply(.toggleMute)
        check(result == .applied(AudioOutput(device: 1, volume: 0.5 + 1.0 / 64, muted: true)), "mute toggles")
        result = await service.apply(.step(increasing: false, fine: false))
        check(hw { $0.muted } == true, "lowering does not unmute")

        hw { $0.controls = [.channel(1), .channel(2)]; $0.channels = [1: 0.25, 2: 0.25]; $0.muted = false }
        result = await service.apply(.step(increasing: true, fine: false))
        check(hw { $0.channels } == [1: 0.3125, 2: 0.3125], "each stereo channel written when no main control")

        hw { $0.controls = [.main]; $0.volume = 0.5; $0.roundsTo = 0.5 }
        check(await service.apply(.step(increasing: true, fine: false)) == .fallbackToNativeKeys,
              "a level the device rounds away falls back to the native keys")
        hw { $0.roundsTo = nil; $0.settable = false }
        check(await service.apply(.step(increasing: true, fine: false)) == .fallbackToNativeKeys, "not settable")
        hw { $0.controls = [] ; $0.settable = true }
        check(await service.apply(.step(increasing: true, fine: false)) == .fallbackToNativeKeys, "no control")
        hw { $0.controls = [.main]; $0.device = nil }
        check(await service.apply(.toggleMute) == .fallbackToNativeKeys, "no output device")

        hw { $0.device = 1; $0.volume = 1 }
        check(await service.apply(.step(increasing: true, fine: false))
              == .applied(AudioOutput(device: 1, volume: 1, muted: false)), "at the top stays applied")
        check(await service.apply(.setVolume(0.25)) == .applied(AudioOutput(device: 1, volume: 0.25, muted: false)),
              "a preset sets the level")
        check(await service.apply(.setVolume(1.5)) == .fallbackToNativeKeys, "an out-of-range preset is refused")
        service.stop()
        check(await service.apply(.toggleMute) == .cancelled, "stopped: cancelled")
    }

    @MainActor
    static func quitRestore() async {
        install([15: FakeDisplay(uuid: "uuid-15")])
        let recovery = DisplaySoundRecovery(system: system)
        let controller = BrightnessController(system: system, recovery: recovery)
        controller.start()
        await until("quit initial read") { controller.currentDisplays.count == 1 }
        _ = await controller.set(0.5, for: id(15))
        check(hw { $0.displays[15]?.gamma != baseline }, "dimmed before quit")
        controller.stop()
        recovery.stop()
        check(hw { $0.displays[15]?.gamma == baseline }, "finding 7: quit restores before stop returns")
        _ = await recovery.perform(.refresh(names: [:]))
        check(await recovery.perform(.set(0.25, id(15))) == nil, "a closed service refuses to dim")
        check(hw { $0.displays[15]?.gamma == baseline }, "finding 7: nothing dims after the quit restore")
        print("finding 7 synchronous quit restore: PASS")
    }

    @MainActor
    static func contendedQuit() async {
        install([14: FakeDisplay(uuid: "uuid-14", ddc: true)])
        let service = BrightnessDisplayService(displays: system.displays)
        _ = await service.perform(.refresh(names: [:]))
        _ = await service.perform(.set(-0.25, id(14)))
        check(hw { $0.displays[14]?.gamma != baseline }, "contended: dimmed before quit")
        let timedOut: Bool = await withCheckedContinuation { continuation in
            discovery.state.withLock {
                $0 = DiscoveryGate.State(armed: true, onEnter: {
                    DispatchQueue.main.async {
                        service.restoreBeforeExit(within: .milliseconds(20))
                        let held = !discovery.state.withLock { $0.finished }
                        discovery.state.withLock { $0.released = true }
                        continuation.resume(returning: held)
                    }
                })
            }
            Task { _ = await service.perform(.refresh(names: [:])) }
        }
        check(timedOut, "contended: quit gives up while a transaction holds the displays")
        await until("finding 9: the transaction in flight restores instead of dimming") {
            hw { $0.displays[14]?.gamma == baseline }
        }
        discovery.state.withLock { $0 = DiscoveryGate.State() }
        let requests = hw { $0.requests }
        check(await service.perform(.refresh(names: [:])) == nil, "contended: closed after a timed-out quit")
        check(hw { $0.requests } == requests, "a closed service touches no display")
        check(hw { $0.displays[14]?.gamma == baseline }, "finding 9: nothing dims after a timed-out quit")
        print("finding 9 contended quit: PASS")
    }

    @MainActor
    static func quitDuringGammaRead() async {
        install([13: FakeDisplay(uuid: "uuid-13")])
        let service = BrightnessDisplayService(displays: system.displays)
        _ = await service.perform(.refresh(names: [:]))
        check(hw { $0.displays[13]?.gamma == baseline }, "gamma read: undimmed before quit")
        let timedOut: Bool = await withCheckedContinuation { continuation in
            gammaRead.state.withLock {
                $0 = DiscoveryGate.State(armed: true, onEnter: {
                    DispatchQueue.main.async {
                        service.restoreBeforeExit(within: .milliseconds(20))
                        let held = !gammaRead.state.withLock { $0.finished }
                        gammaRead.state.withLock { $0.released = true }
                        continuation.resume(returning: held)
                    }
                })
            }
            Task { _ = await service.perform(.set(-0.25, id(13))) }
        }
        check(timedOut, "gamma read: quit gives up while a dim waits on gamma I/O")
        await until("finding 9: a dim blocked in gamma I/O restores after the quit") {
            hw { $0.displays[13]?.gamma == baseline && $0.gammaWrites.filter { $0 == 13 }.count == 2 }
        }
        gammaRead.state.withLock { $0 = DiscoveryGate.State() }
        check(await service.perform(.set(-0.25, id(13))) == nil, "gamma read: closed after a timed-out quit")
        check(hw { $0.displays[13]?.gamma == baseline }, "finding 9: nothing stays dimmed after gamma I/O")
        print("finding 9 quit during gamma read: PASS")
    }

    @MainActor
    static func audioRebind() async {
        install([:])
        let service = AudioLevelsService(system: system)
        service.start()
        await until("listeners bound to the first device") { hw { $0.watched.last ?? nil } == 1 }
        hw { $0.device = 2 }
        check(await service.apply(.setVolume(0.3)) == .applied(AudioOutput(device: 2, volume: 0.3, muted: false)),
              "applied on the new device")
        await until("finding 8: listeners follow the applied device") { hw { $0.watched.last ?? nil } == 2 }
        service.stop()
        print("finding 8 audio rebind: PASS")
    }

    static func mutations() {
        let folder = "Tinycast/Features/Notchcast/DisplaySound/"
        let service = folder + "Service/BrightnessDisplayService.swift"
        let recovery = folder + "Service/DisplaySoundRecovery.swift"
        let cases: [(Int, String, [(String, String, String)], String)] = [
            (1, "module", [(folder + "DisplaySoundAddon.swift",
                            "context.recovery(DisplaySoundRecovery.self) ?? ", "")],
             "finding 1: recovery restores after module teardown"),
            (2, "service", [(service, "if current != written {", "if false {")], "foreign gamma"),
            (3, "service", [
                (service, "@concurrent func restoreAll() async -> Bool", "func restoreAll() -> Bool"),
                (recovery, "await service.restoreAll()", "service.restoreAll()"),
                (recovery, "func restore() {", "func restore() {\n        _ = service.restoreAll()"),
            ], "finding 3: stop returns"),
            (4, "model", [(folder + "Model/MediaLevelKeyPolicy.swift",
                           "if !isDown, let key = physical.removeValue", "if false, let key = physical.removeValue")],
             "finding 4: owned F14 release"),
            (5, "service", [(service, "if control == .ddc {", "if false {")], "finding 5: a step reads"),
            (6, "service", [(folder + "Service/AudioLevelsService.swift",
                             "if case .fallbackToNativeKeys = unmuted", "if false")], "finding 6: a failed unmute"),
            (7, "service", [(recovery,
                             "service.restoreBeforeExit(within: BrightnessRecoveryPolicy.quitWait)",
                             "restore()")], "finding 7: quit restores"),
            (8, "service", [(folder + "Service/AudioLevelsService.swift",
                             "if watchedDevice != next?.device { watch() }",
                             "if previous?.device != next?.device { watch() }")], "finding 8: listeners follow"),
            (9, "service", [(service, "_ = restoreOwed(&state)\n                return nil",
                             "return snapshot")], "finding 9: the transaction in flight restores"),
            (10, "service", [(service, "guard !Task.isCancelled, !closed.load(ordering: .acquiring) else",
                              "guard !Task.isCancelled else")], "a closed service touches no display"),
        ]
        for (finding, harness, edits, expected) in cases {
            do {
                let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: scratch) }
                let test = "Tests/nc-DisplaySound-\(harness)-test.swift"
                let header = try String(contentsOf: root.appendingPathComponent(test), encoding: .utf8)
                var paths = [test]
                for line in header.split(separator: "\n") where line.hasPrefix("// notchcast-sources: ") {
                    for source in line.dropFirst("// notchcast-sources: ".count).split(separator: " ") {
                        let path = String(source)
                        if path.hasSuffix("/*.swift") {
                            let directory = String(path.dropLast("/*.swift".count))
                            paths += try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(directory).path)
                                .filter { $0.hasSuffix(".swift") }.sorted().map { directory + "/" + $0 }
                        } else { paths.append(path) }
                    }
                }
                var inputs: [String] = []
                for path in paths {
                    var source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
                    for (target, original, broken) in edits where target == path {
                        check(source.contains(original), "mutation \(finding) target exists")
                        source = source.replacingOccurrences(of: original, with: broken)
                    }
                    let copy = scratch.appendingPathComponent(URL(fileURLWithPath: path).lastPathComponent)
                    try source.write(to: copy, atomically: true, encoding: .utf8)
                    inputs.append(copy.path)
                }
                let binary = scratch.appendingPathComponent("mutant").path
                let compilation = try runProcess("/usr/bin/xcrun",
                    ["swiftc", "-swift-version", "6", "-parse-as-library"] + inputs + ["-o", binary], scratch: scratch)
                check(compilation.0 == 0, "mutation \(finding) must compile: \(compilation.1)")
                let result = try runProcess(binary, [], scratch: scratch)
                check(result.0 != 0 && result.1.contains(expected),
                      "mutation \(finding) must fail its pin: \(result.1)")
                print("SKIP: hardware only; finding \(finding) planted break: FAIL (expected), \(expected)")
                if finding == 1 {
                    for (path, _, _) in edits {
                        let copy = scratch.appendingPathComponent(URL(fileURLWithPath: path).lastPathComponent)
                        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
                            .write(to: copy, atomically: true, encoding: .utf8)
                    }
                    let rebuilt = try runProcess("/usr/bin/xcrun",
                        ["swiftc", "-swift-version", "6", "-parse-as-library"] + inputs + ["-o", binary], scratch: scratch)
                    check(rebuilt.0 == 0, "finding 1 restored sources compile: \(rebuilt.1)")
                    let restored = try runProcess(binary, [], scratch: scratch)
                    check(restored.0 == 0 && restored.1.contains("finding 1 recovery handoff: PASS"),
                          "finding 1 restored pin passes: \(restored.1)")
                }
                print("SKIP: hardware only; finding \(finding) original sources restored: PASS (originals untouched)")
            } catch { fatalError("mutation \(finding): \(error)") }
        }
    }

    static func runProcess(_ executable: String, _ arguments: [String], scratch: URL) throws -> (Int32, String) {
        let log = scratch.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let output = try FileHandle(forWritingTo: log)
        defer { try? output.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["DISPLAY_SOUND_MUTANT"] = "1"
        environment["SWIFT_BACKTRACE"] = "disable"
        process.environment = environment
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        return (process.terminationStatus, try String(contentsOf: log, encoding: .utf8))
    }
}
