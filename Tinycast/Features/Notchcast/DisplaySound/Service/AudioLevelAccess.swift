import Foundation

/// The default output's volume and mute over CoreAudio, through the first volume control it has.
struct AudioLevelAccess: Sendable {
    let audio: DisplaySoundSystem.Audio

    func output() -> AudioOutput? {
        guard let device = audio.defaultOutput() else { return nil }
        let levels = controls(device).map { audio.volume(device, $0) }
        return AudioOutput(device: device, volume: AudioVolumeControl.volume(levels), muted: audio.muted(device))
    }

    func writeVolume(_ volume: Double, device: UInt32) -> Bool {
        guard volume.isFinite, (0...1).contains(volume), audio.defaultOutput() == device else { return false }
        let controls = controls(device)
        guard !controls.isEmpty, controls.allSatisfy({ audio.canSetVolume(device, $0) }) else { return false }
        for control in controls {
            guard audio.defaultOutput() == device, audio.setVolume(device, control, volume) else { return false }
        }
        return true
    }

    func writeMute(_ muted: Bool, device: UInt32) -> Bool {
        audio.defaultOutput() == device && audio.canSetMute(device) && audio.setMuted(device, muted)
    }

    private func controls(_ device: UInt32) -> [AudioVolumeControl] {
        AudioVolumeControl.chain(has: { audio.has(device, $0) }, stereoChannels: { audio.stereoChannels(device) })
    }
}
