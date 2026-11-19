// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Mihail Antonov
// Adapted from Aural bf4b2b2's SoloistSource.swift: controls take playback back to this Mac first.

import Foundation

extension SpotifyModule {
    func togglePlay() {
        if playback.isPlaying { pause() } else { play() }
    }
    func play() { control(.play(uri: nil)) }
    func pause() { control(.pause) }
    func next() { control(.skipNext) }
    func previous() { control(.skipPrevious) }

    func seek(toMs position: Int) {
        let clamped = max(0, min(position, playback.track?.durationMs ?? position))
        var moved = playback
        moved.position = SpotifyPosition(positionMs: clamped, timestamp: now, speed: playback.isPlaying ? 1 : 0)
        // Soloist sends no `position_sync` for some seeks, so the bar moves on our estimate until it does.
        apply(moved)
        control(.seek(positionMs: clamped))
    }

    /// Spotify's own volume (D19): saved at once and set again on every Soloist start.
    func setVolume(_ level: Int) {
        let value = storeVolume(level)
        var changed = playback
        changed.volume = value
        apply(changed)
        send(.setVolume(value))
    }

    func play(uri: String) { control(.play(uri: uri)) }
    func addToQueue(uri: String) { send(.addToQueue(uri: uri)) }

    /// Takes playback over from the phone or another device and plays here (D34).
    func playHere() { send(.activate, .play(uri: nil)) }

    /// Soloist ignores controls while another device plays, so a press here takes playback back first.
    private func control(_ command: SoloistCommand) {
        if !playback.isActiveDevice, playback.track != nil { send(.activate, command) } else { send(command) }
    }

    /// One task per batch keeps the commands in order on the socket.
    func send(_ commands: SoloistCommand...) {
        guard let link else { return }
        Task {
            for command in commands { try? await link.send(command) }
        }
    }

    func remote(_ command: SpotifyRemoteCommand) {
        switch command {
        case .toggle: togglePlay()
        case .play: play()
        case .pause: pause()
        case .next: next()
        case .previous: previous()
        case .seek(let seconds): seek(toMs: Int(seconds * 1000))
        }
    }
}
