// notchcast-linux-ok
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
        check(BrightnessLevel(-0.25).readout == "0%", "the darkest extra dimming reads 0%")
        check(BrightnessLevel(-0.125).readout == "10%", "extra dimming reads as a percent, never a word")
        check(BrightnessLevel(0).readout == "20%", "the system minimum reads 20%, a fifth of the bar")
        check(BrightnessLevel(0.03125).readout == "23%", "Settings rounds 22.5% up, as the island does")
        check(BrightnessLevel(1).readout == "100%", "the brightest reads 100%")
        check(BrightnessLevel(0.125, softwareOnly: true).readout == "13%", "software dimming spans 0…1 only")
        check(BrightnessLevel(0, softwareOnly: true).readout == "0%", "software dimming's floor reads 0%")
        var previous = -1
        for step in -16...64 {
            let level = BrightnessLevel(Double(step) / 64)
            guard let percent = Int(level.readout.dropLast()) else { return check(false, "\(level.readout) is a percent") }
            check((0...100).contains(percent) && percent >= previous, "\(level.value) reads \(percent)% after \(previous)%")
            check(IslandLevel(source: "brightness", symbol: "sun.max.fill", label: "Brightness", value: level.value,
                              range: level.range).readout == level.readout, "the island and Settings agree at \(level.value)")
            previous = percent
        }

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

        // Reconnection drops extra dimming; software dimming stays above its floor.
        check(BrightnessLevel(-0.25).reconnected() == BrightnessLevel(0), "deep extra dimming is dropped")
        check(BrightnessLevel(-0.05).reconnected() == BrightnessLevel(0), "shallow extra dimming is dropped")
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
        check(DisplayDDC.request(.luminance) == [0x82, 0x01, 0x10, 0x6E ^ 0x51 ^ 0x82 ^ 0x01 ^ 0x10], "request packet")
        check(DisplayDDC.write(.luminance, 50) == [0x84, 0x03, 0x10, 0, 50, 0x6E ^ 0x51 ^ 0x84 ^ 0x03 ^ 0x10 ^ 0 ^ 50],
              "write packet")
        var reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 100, 0x00, 40]
        reply.append(reply.reduce(UInt8(0x50), ^))
        check(DisplayDDC.parse(reply, .luminance)! == (40, 100), "reply parsed")
        check(DisplayDDC.parse(reply, .volume) == nil, "a reply for another code is not this one")
        var corrupt = reply
        corrupt[9] = 41
        check(DisplayDDC.parse(corrupt, .luminance) == nil, "bad checksum dropped")
        check(DisplayDDC.deviceValue(-0.2, maximum: 100) == 0, "extra dimming writes 0")
        check(DisplayDDC.deviceValue(0.5, maximum: 80) == 40, "scaled to the monitor's maximum")
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
        extraDimming()
        speakers()
        print("nc-DisplaySound-model-test: PASS")
    }

    static func extraDimming() {
        let off = BrightnessLevel(-0.2, extraDimming: false)
        check(off.value == 0 && off.range == 0...1 && !off.isDimmed, "off: the backlight minimum is the floor")
        check(off.stepped(up: false, fine: false).value == 0, "off: keys stop at the backlight minimum")
        check(off.readout == "0%" && BrightnessLevel(1, extraDimming: false).readout == "100%", "off: 0…100 is the backlight")
        check(!off.stepped(up: true, fine: true).extraDimming, "a step keeps the setting")
        check(!BrightnessLevel(-0.1).refreshed(hardware: 0.3).allowing(extraDimming: false).extraDimming, "kept")
        check(BrightnessLevel(-0.1).allowing(extraDimming: false) == off, "turning it off lifts a dimmed level")
        check(BrightnessLevel(-0.1).withoutExtraDimming() == BrightnessLevel(0), "sleep drops extra dimming")
        let software = BrightnessLevel(0.3, softwareOnly: true)
        check(software.withoutExtraDimming() == software, "software dimming is no extra")
        check(software.allowing(extraDimming: false).value == 0.3, "software dimming ignores the setting")
        var level = BrightnessLevel(1, extraDimming: false)
        for _ in 0..<40 { level = level.stepped(up: false, fine: false) }
        check(level.value == 0 && level.picture == 1, "off: twenty presses down never dim the picture")
    }

    static func speakers() {
        // VCP 0x62 volume and 0x8D mute packets, and a reply for each.
        check(DisplayDDC.request(.volume) == DisplayDDC.seal([0x82, 0x01, 0x62]), "volume request")
        check(DisplayDDC.request(.mute) == DisplayDDC.seal([0x82, 0x01, 0x8D]), "mute request")
        check(DisplayDDC.write(.volume, 300) == DisplayDDC.seal([0x84, 0x03, 0x62, 0x01, 0x2C]), "16-bit volume")
        check(DisplayDDC.write(.mute, DisplayDDC.muteValue(true)) == DisplayDDC.seal([0x84, 0x03, 0x8D, 0, 1]), "mute")
        check(DisplayDDC.write(.mute, DisplayDDC.muteValue(false)) == DisplayDDC.seal([0x84, 0x03, 0x8D, 0, 2]), "unmute")
        var reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x62, 0x00, 0x00, 100, 0x00, 30]
        reply.append(reply.reduce(UInt8(0x50), ^))
        check(DisplayDDC.parse(reply, .volume)! == (30, 100), "volume reply parsed")
        check(DisplayDDC.muted(1) == true && DisplayDDC.muted(2) == false && DisplayDDC.muted(0) == nil, "mute values")
        check(DisplayDDC.share(30, maximum: 100) == 0.3 && DisplayDDC.share(5, maximum: 0) == 0, "share")

        // Which display's speakers the output is.
        let dell = DisplaySpeaker.Display(uuid: "A", name: "DELL U2720Q")
        let lg = DisplaySpeaker.Display(uuid: "B", name: "LG HDR 4K")
        check(DisplaySpeaker.target(outputName: " dell u2720q", displays: [dell, lg]) == "A", "matched by name")
        check(DisplaySpeaker.target(outputName: "HDMI", displays: [lg]) == "B", "the only external display")
        check(DisplaySpeaker.target(outputName: "", displays: [dell]) == "A", "an unnamed output, one display")
        check(DisplaySpeaker.target(outputName: "HDMI", displays: [dell, lg]) == nil, "two unnamed: system")
        let twin = DisplaySpeaker.Display(uuid: "C", name: "DELL U2720Q")
        check(DisplaySpeaker.target(outputName: "DELL U2720Q", displays: [dell, twin]) == nil, "twins: system")
        check(DisplaySpeaker.target(outputName: "DELL U2720Q", displays: []) == nil, "no display: system")

        // Steps on the monitor's scale, mute and unmute.
        let up = DisplaySpeaker.plan(.step(increasing: true, fine: false), volume: (50, 100), mute: 2, remembered: nil)!
        check(up.level == DisplaySpeakerLevel(volume: 0.56, muted: false), "1/16 up on a 0…100 scale: \(up.level)")
        check(up.packets == [DisplayDDC.write(.volume, 56)], "one volume write")
        let fine = DisplaySpeaker.plan(.step(increasing: false, fine: true), volume: (50, 100), mute: nil,
                                       remembered: DisplaySpeakerLevel(volume: 0.5, muted: true))!
        check(fine.packets == [DisplayDDC.write(.volume, 48)] && fine.level.muted, "1/64 down keeps the remembered mute")
        let unmute = DisplaySpeaker.plan(.step(increasing: true, fine: false), volume: (10, 10), mute: 1, remembered: nil)!
        check(unmute.packets == [DisplayDDC.write(.mute, 2)] && unmute.level == DisplaySpeakerLevel(volume: 1, muted: false),
              "volume up at the top unmutes, writing no volume")
        let coarse = DisplaySpeaker.plan(.step(increasing: true, fine: true), volume: (5, 10), mute: 2, remembered: nil)!
        check(coarse.packets == [DisplayDDC.write(.volume, 6)], "a step the scale rounds away moves one unit")
        let floor = DisplaySpeaker.plan(.step(increasing: false, fine: false), volume: (0, 100), mute: 2, remembered: nil)!
        check(floor.packets.isEmpty && floor.level.volume == 0, "at 0 nothing is written")
        let toggled = DisplaySpeaker.plan(.toggleMute, volume: (40, 100), mute: 2, remembered: nil)!
        check(toggled.packets == [DisplayDDC.write(.mute, 1)] && toggled.level == DisplaySpeakerLevel(volume: 0.4, muted: true),
              "mute toggles from what the monitor reports")
        check(DisplaySpeaker.plan(.toggleMute, volume: (40, 100), mute: nil,
                                  remembered: DisplaySpeakerLevel(volume: 0.4, muted: false)) == nil,
              "a monitor without mute leaves the key to macOS")
        let quarter = DisplaySpeakerLevel(volume: 0.25, muted: true)
        check(DisplaySpeaker.restore(quarter, maximum: 80, hasMute: true)
              == [DisplayDDC.write(.volume, 20), DisplayDDC.write(.mute, 1)], "restore on the monitor's own scale")
        check(DisplaySpeaker.restore(quarter, maximum: 80, hasMute: false) == [DisplayDDC.write(.volume, 20)],
              "restore sends no mute value to a monitor without mute")

        // The per-display store.
        var store = DisplaySpeakerStore()
        store.remember(DisplaySpeakerLevel(volume: 0.3, muted: false), for: "A")
        store.remember(DisplaySpeakerLevel(volume: 0.7, muted: true), for: "B")
        check(DisplaySpeakerStore(data: store.data) == store, "the store round-trips")
        check(DisplaySpeakerStore(data: Data("junk".utf8)) == DisplaySpeakerStore(), "an unreadable store starts empty")
        check(DisplaySpeakerStore(data: nil).levels.isEmpty, "no store starts empty")
        check(store.returning(from: ["A"], to: ["A", "B", "C"]) == ["B"], "only a returning display with a level")
        check(store.returning(from: [], to: ["B", "A"]) == ["A", "B"], "in a stable order")
        check(store.returning(from: ["A", "B"], to: ["A"]).isEmpty, "a display leaving restores nothing")
    }
}
