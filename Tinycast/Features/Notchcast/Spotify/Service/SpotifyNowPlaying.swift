import Foundation
import MediaPlayer

/// macOS Now Playing: Control Center shows the song and media keys reach Soloist (decision D9).
@MainActor
enum SpotifyNowPlaying {
    static func update(_ playback: SpotifyPlayback?, elapsed: TimeInterval) {
        let center = MPNowPlayingInfoCenter.default()
        guard let playback, let track = playback.track else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        center.nowPlayingInfo = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artistLine,
            MPMediaItemPropertyAlbumTitle: track.album ?? "",
            MPMediaItemPropertyPlaybackDuration: Double(track.durationMs) / 1000,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: playback.isPlaying ? 1.0 : 0.0,
        ]
        center.playbackState = playback.isPlaying ? .playing : .paused
    }

    private static var targets: [(MPRemoteCommand, Any)] = []

    static func commands(_ handler: (@MainActor (SpotifyRemoteCommand) -> Void)?) {
        for (command, target) in targets { command.removeTarget(target) }
        targets = []
        guard let handler else { return }
        let center = MPRemoteCommandCenter.shared()
        func bind(_ command: MPRemoteCommand,
                  _ action: @escaping @Sendable (MPRemoteCommandEvent) -> SpotifyRemoteCommand?) {
            let target = command.addTarget { event in
                guard let mapped = action(event) else { return .commandFailed }
                Task { @MainActor in handler(mapped) }
                return .success
            }
            targets.append((command, target))
        }
        bind(center.togglePlayPauseCommand) { _ in .toggle }
        bind(center.playCommand) { _ in .play }
        bind(center.pauseCommand) { _ in .pause }
        bind(center.nextTrackCommand) { _ in .next }
        bind(center.previousTrackCommand) { _ in .previous }
        bind(center.changePlaybackPositionCommand) { event in
            (event as? MPChangePlaybackPositionCommandEvent).map { .seek($0.positionTime) }
        }
    }
}
