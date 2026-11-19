// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Mihail Antonov
// Adapted from Aural bf4b2b2's PlaybackModels.swift and SoloistMapping.swift: state from Soloist events.

import Foundation

struct SpotifyTrack: Sendable, Equatable, Codable {
    /// The Spotify URI, `spotify:track:…`.
    let id: String
    let title: String
    let artists: [String]
    let album: String?
    let artworkURL: URL?
    let thumbnailURL: URL?
    let durationMs: Int

    var artistLine: String { artists.joined(separator: ", ") }
}

enum SpotifyStatus: String, Sendable, Equatable {
    case idle, playing, paused, buffering
}

/// "At `timestamp` it was at `positionMs`, moving at `speed`", so no per-second events are needed.
struct SpotifyPosition: Sendable, Equatable {
    var positionMs: Int
    var timestamp: Date
    /// 1 while playing, 0 while paused.
    var speed: Double

    static let zero = SpotifyPosition(positionMs: 0, timestamp: .distantPast, speed: 0)

    func current(at now: Date, durationMs: Int?) -> Int {
        let estimate = max(0, positionMs + Int(now.timeIntervalSince(timestamp) * 1000 * speed))
        guard let durationMs, durationMs > 0 else { return estimate }
        return min(estimate, durationMs)
    }
}

enum SpotifyAction: String, Sendable, Hashable {
    case play, pause, seek, skipNext, skipPrevious, addToQueue
}

struct SpotifyQueueEntry: Sendable, Equatable, Identifiable {
    enum Source: Sendable, Equatable { case context, queue, autoplay }
    let id: String
    let track: SpotifyTrack
    let source: Source
}

struct SpotifyPlayback: Sendable, Equatable {
    var status = SpotifyStatus.idle
    var track: SpotifyTrack?
    var position = SpotifyPosition.zero
    /// 0–100, Soloist's own volume.
    var volume = 0
    var actions: Set<SpotifyAction> = []
    /// This Mac is the device Spotify plays on.
    var isActiveDevice = false
    var isLoggedIn = false
    var contextName: String?
    var upNext: [SpotifyQueueEntry] = []

    var isPlaying: Bool { status == .playing || status == .buffering }

    /// The state after one event; events that do not touch playback leave it as it was.
    func applying(_ event: SoloistEvent) -> SpotifyPlayback {
        var next = self
        switch event {
        case .playbackState(let state):
            next.status = SpotifyStatus(rawValue: state.status) ?? .idle
            next.track = state.item.flatMap(SpotifyTrack.init(soloist:))
            if let position = state.position { next.position = SpotifyPosition(soloist: position) }
            if let volume = state.volume { next.volume = volume }
            if let isActive = state.isActive { next.isActiveDevice = isActive }
            next.contextName = Self.contextName(state.context)
            next.actions = Set((state.availableActions ?? [:]).keys.compactMap(SpotifyAction.init(soloist:)))
        case .trackChanged(let item):
            next.track = item.flatMap(SpotifyTrack.init(soloist:))
        case .playbackChanged(let status):
            next.status = SpotifyStatus(rawValue: status) ?? .idle
        case .positionSync(let position):
            next.position = SpotifyPosition(soloist: position)
        case .volumeChanged(let volume):
            next.volume = volume
        case .deviceChanged(let isActive):
            next.isActiveDevice = isActive
        case .authState(let loggedIn, let isActive):
            next.isLoggedIn = loggedIn
            next.isActiveDevice = isActive
        case .contextChanged(let context):
            next.contextName = Self.contextName(context)
        case .queueChanged(let upcoming):
            next.upNext = SpotifyQueueEntry.entries(upcoming)
        case .commandResult, .error, .unknown:
            break
        }
        return next
    }

    /// A single track as context has no useful name.
    private static func contextName(_ context: SoloistWire.Entity?) -> String? {
        guard let context, context.entityType != "track", context.entityType != "unknown",
              let name = context.decorations?.identity?.name, !name.isEmpty else { return nil }
        return name
    }
}

extension SpotifyQueueEntry {
    /// Placeholders and episodes are left out.
    static func entries(_ upcoming: [SoloistWire.QueueEntry]) -> [SpotifyQueueEntry] {
        upcoming.enumerated().compactMap { offset, entry in
            guard let track = SpotifyTrack(soloist: entry.item), track.id.hasPrefix("spotify:track:") else { return nil }
            let source: Source = switch entry.source {
            case "queue": .queue
            case "autoplay": .autoplay
            default: .context
            }
            return SpotifyQueueEntry(id: entry.uid ?? "\(offset)-\(track.id)", track: track, source: source)
        }
    }
}

extension SpotifyPosition {
    init(soloist position: SoloistWire.Position) {
        self.init(positionMs: position.positionMs,
                  timestamp: Date(timeIntervalSince1970: Double(position.timestampMs) / 1000), speed: position.speed)
    }
}

extension SpotifyAction {
    init?(soloist name: String) {
        switch name {
        case "play": self = .play
        case "pause": self = .pause
        case "seek": self = .seek
        case "skip_next": self = .skipNext
        case "skip_prev": self = .skipPrevious
        case "add_to_queue": self = .addToQueue
        default: return nil
        }
    }
}

extension SpotifyTrack {
    /// Nil for placeholder entities without a URI or a name.
    init?(soloist entity: SoloistWire.Entity) {
        guard let uri = entity.uri, !uri.isEmpty, let title = entity.decorations?.identity?.name else { return nil }
        let decorations = entity.decorations
        let covers = decorations?.visualIdentity?.cover ?? []
        self.init(id: uri, title: title,
                  artists: (decorations?.creators ?? []).compactMap { $0.entity.decorations?.identity?.name },
                  album: decorations?.parent?.entity.decorations?.identity?.name,
                  artworkURL: Self.cover(covers, preferring: ["large", "default", "xlarge", "small"]),
                  thumbnailURL: Self.cover(covers, preferring: ["small", "default"]),
                  durationMs: decorations?.playback?.durationMs ?? 0)
    }

    private static func cover(_ covers: [SoloistWire.Cover], preferring sizes: [String]) -> URL? {
        for size in sizes {
            if let url = covers.first(where: { $0.size == size }).flatMap({ URL(string: $0.url) }) { return url }
        }
        return covers.first.flatMap { URL(string: $0.url) }
    }
}
