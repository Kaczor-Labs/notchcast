// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/NotchcastMediaKey.swift
// notchcast-sources: Tinycast/Features/Notchcast/DisplaySound/Model/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandLevelDwell.swift

import Foundation

func check(_ condition: Bool, _ message: String) {
    guard condition else { fatalError("nc-DisplaySound-model-test: \(message)") }
}

func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.000_001 }

func media(_ key: MediaLevelKey, down: Bool = true, repeat repeating: Bool = false) -> NotchcastMediaKey {
    NotchcastMediaKey(subtype: 8, data1: key.rawValue << 16 | (down ? 0xA : 0xB) << 8 | (repeating ? 1 : 0))!
}

@main
enum DisplaySoundModelTests {
    static func main() {
        // Range −0.25…1, software dimming 0…1.
        check(BrightnessLevel(-1).value == -0.25 && BrightnessLevel(2).value == 1, "clamped to −0.25…1")
        check(BrightnessLevel(-1, softwareOnly: true).value == 0, "software range starts at 0")
        check(BrightnessLevel(0.5).range == -0.25...1, "hardware range")
        check(BrightnessLevel(0.5, softwareOnly: true).range == 0...1, "software range")
        check(BrightnessLevel(.nan).value == 0, "NaN reads as 0")
        check(BrightnessLevel(0).picture == 1 && !BrightnessLevel(0).isDimmed, "0 keeps the full picture")
        check(close(BrightnessLevel(-0.25).picture, BrightnessLevel.minimumPicture), "−0.25 is the deepest dim")
        check(BrightnessLevel(-0.25).hardware == 0, "extra dimming leaves the backlight at 0")
        check(BrightnessLevel(0.125).readout == "13%", "Settings rounds 12.5% up, as the island does")
        check(BrightnessLevel(0.625).readout == "63%", "Settings rounds 62.5% up, as the island does")
        check(BrightnessLevel(-0.125).readout == "Dim", "Settings names extra dimming")

        // 1/16 steps, 1/64 fine, snapping onto the grid.
        check(close(BrightnessLevel(0.5).stepped(up: true, fine: false).value, 0.5625), "1/16 up")
        check(close(BrightnessLevel(0.5).stepped(up: false, fine: true).value, 0.5 - 1.0 / 64), "1/64 down")
        check(close(BrightnessLevel(0.51).stepped(up: true, fine: false).value, 0.5625), "snaps up to the grid")
        check(close(BrightnessLevel(0.51).stepped(up: false, fine: false).value, 0.5), "snaps down to the grid")
        check(close(BrightnessLevel(0).stepped(up: false, fine: false).value, -0.0625), "steps below 0 into dimming")
        check(BrightnessLevel(-0.25).stepped(up: false, fine: false).value == -0.25, "stops at −0.25")
        check(BrightnessLevel(1).stepped(up: true, fine: true).value == 1, "stops at 1")
        check(BrightnessLevel(0, softwareOnly: true).stepped(up: false, fine: false).value == 0, "software stops at 0")
        var level = BrightnessLevel(-0.25)
        var steps = 0
        while level.value < 1 { level = level.stepped(up: true, fine: false); steps += 1 }
        check(steps == 20, "−0.25…1 is twenty 1/16 steps")

        // The reconnection floor.
        let deep = BrightnessLevel(-0.25)
        check(close(deep.reconnected().picture, BrightnessRecoveryPolicy.reconnectionDimFloor), "deep dim lifts to floor")
        check(BrightnessLevel(-0.05).reconnected() == BrightnessLevel(-0.05), "shallow dim is kept")
        check(BrightnessLevel(0.4).reconnected() == BrightnessLevel(0.4), "an undimmed level is kept")
        let softDeep = BrightnessLevel(0, softwareOnly: true)
        check(close(softDeep.reconnected().picture, 0.25) && softDeep.reconnected().softwareOnly, "software floor")
        check(close(BrightnessLevel(picture: 0.6, softwareOnly: false).picture, 0.6), "picture round-trips")

        // A backlight read at 0 keeps the dimming already below it.
        check(BrightnessLevel(-0.1).refreshed(hardware: 0).value == -0.1, "0 reading keeps extra dim")
        check(BrightnessLevel(-0.1).refreshed(hardware: 0.3).value == 0.3, "a real reading wins")

        // Gamma: un-dim is the baseline, bit for bit.
        let gamma = BrightnessGamma(red: [0, 0.5, 1], green: [0, 0.4, 0.9], blue: [0.1, 0.5, 1])
        check(gamma.scaled(1) == gamma && gamma.scaled(2) == gamma, "factor ≥1 is the baseline")
        check(gamma.scaled(0.5).red == [0, 0.25, 0.5], "scaled")

        // DDC packets and outcomes.
        check(BrightnessDDC.request() == [0x82, 0x01, 0x10, 0x6E ^ 0x51 ^ 0x82 ^ 0x01 ^ 0x10], "request packet")
        check(BrightnessDDC.write(50) == [0x84, 0x03, 0x10, 0, 50, 0x6E ^ 0x51 ^ 0x84 ^ 0x03 ^ 0x10 ^ 0 ^ 50],
              "write packet")
        var reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 100, 0x00, 40]
        reply.append(reply.reduce(UInt8(0x50), ^))
        check(BrightnessDDC.parse(reply)! == (40, 100), "reply parsed")
        var corrupt = reply
        corrupt[9] = 41
        check(BrightnessDDC.parse(corrupt) == nil, "bad checksum dropped")
        check(BrightnessDDC.deviceValue(-0.2, maximum: 100) == 0, "extra dimming writes 0")
        check(BrightnessDDC.deviceValue(0.5, maximum: 80) == 40, "scaled to the monitor's maximum")
        check(BrightnessRecoveryPolicy.channelOutcome(writeAccepted: true, reply: nil) == .writeOnly, "write-only")
        check(BrightnessRecoveryPolicy.channelOutcome(writeAccepted: false, reply: nil) == .dead, "dead")
        check(BrightnessRecoveryPolicy.channelOutcome(writeAccepted: false, reply: (1, 2)) == .live(current: 1, maximum: 2),
              "a reply is live")
        check(!BrightnessRecoveryPolicy.retries(.live(current: 1, maximum: 2), repliedThisSession: true), "live: no retry")
        check(BrightnessRecoveryPolicy.retries(.writeOnly, repliedThisSession: true), "silent after a reply: retry")
        check(!BrightnessRecoveryPolicy.retries(.writeOnly, repliedThisSession: false), "never replied: no retry")

        // Non-Apple keyboards.
        check(BrightnessFunctionKeys.functionKeysAdjustBrightness(symbolicHotKeys: nil), "absent means on")
        check(!BrightnessFunctionKeys.functionKeysAdjustBrightness(symbolicHotKeys: ["53": ["enabled": false]]),
              "disabled shortcut 53 turns F14 off")
        check(BrightnessFunctionKeys.functionKeysAdjustBrightness(symbolicHotKeys: ["53": ["enabled": true]]), "on")
        check(BrightnessFunctionKeys.key(keyCode: 144, modified: true, functionKeysAdjustBrightness: false)
              == .brightnessUp, "144 is always brightness up")
        check(BrightnessFunctionKeys.key(keyCode: 107, modified: false, functionKeysAdjustBrightness: true)
              == .brightnessDown, "F14 dims")
        check(BrightnessFunctionKeys.key(keyCode: 107, modified: true, functionKeysAdjustBrightness: true) == nil,
              "modified F14 is the system's")
        check(BrightnessFunctionKeys.key(keyCode: 113, modified: false, functionKeysAdjustBrightness: false) == nil,
              "F15 passes when its shortcut is off")

        // The shared media-level key policy.
        var policy = MediaLevelKeyPolicy()
        let all = Set(MediaLevelKey.allCases)
        check(policy.decide(media(.volumeUp, repeat: true), modifiers: 0, enabled: all) == .pass, "unowned repeat passes")
        check(policy.decide(media(.volumeUp), modifiers: 0, enabled: all) == .press(.volumeUp, fine: false), "press")
        for _ in 0..<5 {
            check(policy.decide(media(.volumeUp, repeat: true), modifiers: 0, enabled: all)
                  == .press(.volumeUp, fine: false), "an owned native repeat never passes")
        }
        check(policy.decide(media(.volumeUp), modifiers: 0, enabled: all) == .swallow, "a second down is swallowed")
        check(policy.decide(media(.volumeUp, down: false), modifiers: 0, enabled: all) == .swallow, "owned up")
        check(policy.decide(media(.volumeUp, down: false), modifiers: 0, enabled: all) == .pass, "unowned up passes")
        check(policy.decide(media(.mute), modifiers: 0, enabled: all) == .press(.mute, fine: false), "mute")
        check(policy.decide(media(.mute, repeat: true), modifiers: 0, enabled: all) == .swallow, "mute toggles once")
        check(policy.decide(media(.volumeDown), modifiers: 0xA0000, enabled: all) == .press(.volumeDown, fine: true),
              "⌥⇧ is the fine step")
        check(policy.decide(media(.brightnessUp), modifiers: 0x80000, enabled: all) == .pass, "⌥ alone passes")
        check(policy.decide(media(.brightnessUp), modifiers: 0x100000, enabled: all) == .pass, "⌘ passes")
        check(policy.decide(media(.brightnessUp), modifiers: 0x800000, enabled: all) == .press(.brightnessUp, fine: false),
              "fn does not count as a shortcut modifier")
        check(policy.decide(media(.volumeUp), modifiers: 0, enabled: MediaLevelKey.brightness) == .pass,
              "a key outside the enabled set passes")
        check(policy.decide(keyCode: 107, isDown: true, isRepeat: false, modifiers: 0,
                            functionKeysAdjustBrightness: true, enabled: all) == .press(.brightnessDown, fine: false),
              "F14 presses brightness down")
        check(policy.decide(keyCode: 107, isDown: true, isRepeat: true, modifiers: 0,
                            functionKeysAdjustBrightness: true, enabled: all) == .press(.brightnessDown, fine: false),
              "F14 repeat is owned")
        policy.reset()
        check(policy.decide(keyCode: 107, isDown: true, isRepeat: false, modifiers: 0,
                            functionKeysAdjustBrightness: true, enabled: all) == .press(.brightnessDown, fine: false),
              "finding 4: F14 initial down")
        check(policy.decide(keyCode: 107, isDown: false, isRepeat: false, modifiers: 0x20000,
                            functionKeysAdjustBrightness: false, enabled: all) == .swallow,
              "finding 4: owned F14 release ignores changed modifiers and preference")
        check(policy.decide(keyCode: 107, isDown: true, isRepeat: false, modifiers: 0,
                            functionKeysAdjustBrightness: true, enabled: all) == .press(.brightnessDown, fine: false),
              "finding 4: next F14 down works after Shift release")
        policy.reset()
        check(policy.decide(keyCode: 107, isDown: false, isRepeat: false, modifiers: 0,
                            functionKeysAdjustBrightness: true, enabled: all) == .pass, "reset forgets held keys")
        check(policy.decide(keyCode: 0, isDown: true, isRepeat: false, modifiers: 0,
                            functionKeysAdjustBrightness: true, enabled: all) == .pass, "other keys pass")

        // Volume steps: 16, 64 fine, rounded-away levels skipped.
        check(VolumeStepPolicy.candidates(from: 0.5, increasing: true, fine: false) == [0.5625, 0.625], "16 up")
        check(VolumeStepPolicy.candidates(from: 0.5, increasing: false, fine: true)
              == [31.0 / 64, 30.0 / 64, 29.0 / 64, 28.0 / 64], "64 down")
        check(VolumeStepPolicy.candidates(from: 1, increasing: true, fine: false) == [1], "at the top stays at 1")
        check(VolumeStepPolicy.candidates(from: 0, increasing: false, fine: false) == [0], "at the bottom stays at 0")
        check(VolumeStepPolicy.candidates(from: .nan, increasing: true, fine: false).isEmpty, "NaN has none")
        check(VolumeStepPolicy.advanced(from: 0.5, to: 0.51, increasing: true), "moved up")
        check(!VolumeStepPolicy.advanced(from: 0.5, to: 0.50001, increasing: true), "within tolerance is no move")

        // The CoreAudio fallback chain.
        check(AudioVolumeControl.chain(has: { _ in true }, stereoChannels: { [1, 2] }) == [.virtualMain], "virtual first")
        check(AudioVolumeControl.chain(has: { $0 != .virtualMain }, stereoChannels: { [1, 2] }) == [.main], "then main")
        check(AudioVolumeControl.chain(has: { $0 == .channel(1) || $0 == .channel(2) }, stereoChannels: { [2, 1, 2] })
              == [.channel(1), .channel(2)], "then each stereo channel, sorted and unique")
        check(AudioVolumeControl.chain(has: { $0 == .channel(2) }, stereoChannels: { [1, 2] }) == [.channel(2)],
              "channels without a control are dropped")
        check(AudioVolumeControl.chain(has: { _ in false }, stereoChannels: { nil }).isEmpty, "nothing to control")
        check(AudioVolumeControl.volume([0.4, 0.6]) == 0.5, "channel average")
        check(AudioVolumeControl.volume([0.4, nil]) == nil && AudioVolumeControl.volume([]) == nil, "unreadable")
        let before = AudioOutput(device: 1, volume: 0.5, muted: false)
        check(AudioOutput(device: 1, volume: 0.6, muted: false).changed(from: before), "volume change")
        check(AudioOutput(device: 1, volume: 0.5, muted: true).changed(from: before), "mute change")
        check(!AudioOutput(device: 2, volume: 0.6, muted: false).changed(from: before), "a new device is no change")
        check(!before.changed(from: nil), "first read is no change")
        print("nc-DisplaySound-model-test: PASS")
    }
}
