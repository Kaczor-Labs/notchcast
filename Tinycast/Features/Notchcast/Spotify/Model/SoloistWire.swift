// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Mihail Antonov
// Adapted from Aural bf4b2b2's SoloistMessages.swift: Soloist's WebSocket commands and events.

import Foundation

/// A command for Soloist's WebSocket API, sent as one JSON text frame.
enum SoloistCommand: Sendable, Equatable {
    case getState
    case play(uri: String?)
    case pause
    case skipNext
    case skipPrevious
    case seek(positionMs: Int)
    case setVolume(Int)
    case addToQueue(uri: String)
    /// Makes this Mac Spotify's active Connect device.
    case activate

    var name: String {
        switch self {
        case .getState: "get_state"
        case .play: "play"
        case .pause: "pause"
        case .skipNext: "skip_next"
        case .skipPrevious: "skip_prev"
        case .seek: "seek"
        case .setVolume: "set_volume"
        case .addToQueue: "add_to_queue"
        case .activate: "activate"
        }
    }

    func encoded() -> String {
        var object: [String: Any] = ["type": "command", "command": name]
        switch self {
        case .play(let uri): if let uri { object["uri"] = uri }
        case .addToQueue(let uri): object["uri"] = uri
        case .seek(let positionMs): object["position_ms"] = positionMs
        case .setVolume(let volume): object["volume"] = min(100, max(0, volume))
        case .getState, .pause, .skipNext, .skipPrevious, .activate: break
        }
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}

/// One event from Soloist; an unknown type is ignored rather than an error.
enum SoloistEvent: Sendable, Equatable {
    case authState(loggedIn: Bool, isActive: Bool)
    case playbackState(SoloistWire.PlaybackState)
    case trackChanged(SoloistWire.Entity?)
    case playbackChanged(status: String)
    case positionSync(SoloistWire.Position)
    case volumeChanged(Int)
    case deviceChanged(isActive: Bool)
    case queueChanged(upcoming: [SoloistWire.QueueEntry])
    case contextChanged(SoloistWire.Entity?)
    case commandResult(command: String)
    case error(message: String)
    case unknown(type: String)

    static func decode(_ data: Data) throws -> SoloistEvent {
        let decoder = JSONDecoder()
        let type = try decoder.decode(SoloistWire.Envelope.self, from: data).type
        func payload<T: Decodable>(_: T.Type) throws -> T { try decoder.decode(T.self, from: data) }
        switch type {
        case "auth_state":
            let message = try payload(SoloistWire.AuthState.self)
            return .authState(loggedIn: message.loggedIn, isActive: message.isActive ?? false)
        case "playback_state": return .playbackState(try payload(SoloistWire.PlaybackState.self))
        case "track_changed": return .trackChanged(try payload(SoloistWire.ItemMessage.self).item)
        case "playback_changed": return .playbackChanged(status: try payload(SoloistWire.StatusMessage.self).status)
        case "position_sync": return .positionSync(try payload(SoloistWire.PositionMessage.self).position)
        case "volume_changed": return .volumeChanged(try payload(SoloistWire.VolumeMessage.self).volume)
        case "device_changed": return .deviceChanged(isActive: try payload(SoloistWire.DeviceMessage.self).isActive)
        case "queue_changed": return .queueChanged(upcoming: try payload(SoloistWire.QueueMessage.self).upcoming ?? [])
        case "context_changed": return .contextChanged(try payload(SoloistWire.ContextMessage.self).context)
        case "command_result": return .commandResult(command: try payload(SoloistWire.ResultMessage.self).command)
        case "error": return .error(message: try payload(SoloistWire.ErrorMessage.self).message)
        default: return .unknown(type: type)
        }
    }
}

/// Decodable mirrors of only the fields Notchcast reads; wire names stay visible in `CodingKeys`.
enum SoloistWire {
    struct Envelope: Decodable { let type: String }

    struct AuthState: Decodable {
        let loggedIn: Bool
        let isActive: Bool?
        enum CodingKeys: String, CodingKey { case loggedIn = "logged_in", isActive = "is_active" }
    }

    struct PlaybackState: Decodable, Sendable, Equatable {
        let status: String
        let item: Entity?
        let position: Position?
        let volume: Int?
        let isActive: Bool?
        let context: Entity?
        let availableActions: [String: Ignored]?
        enum CodingKeys: String, CodingKey {
            case status, item, position, volume, context
            case isActive = "is_active", availableActions = "available_actions"
        }
    }

    struct Position: Decodable, Sendable, Equatable {
        let positionMs: Int
        /// Unix epoch milliseconds on Soloist's clock.
        let timestampMs: Int64
        let speed: Double
        enum CodingKeys: String, CodingKey { case speed, positionMs = "position_ms", timestampMs = "timestamp_ms" }
    }

    /// Soloist's envelope for tracks, albums, playlists and the rest.
    struct Entity: Decodable, Sendable, Equatable {
        let uri: String?
        let entityType: String?
        let decorations: Decorations?
        enum CodingKeys: String, CodingKey { case uri, decorations, entityType = "entity_type" }
    }

    struct Decorations: Decodable, Sendable, Equatable {
        let identity: Identity?
        let visualIdentity: VisualIdentity?
        let parent: Related?
        let creators: [Related]?
        let playback: Playback?
        enum CodingKeys: String, CodingKey {
            case identity, parent, creators, playback, visualIdentity = "visual_identity"
        }
    }

    struct Identity: Decodable, Sendable, Equatable { let name: String? }
    struct VisualIdentity: Decodable, Sendable, Equatable { let cover: [Cover]? }

    struct Cover: Decodable, Sendable, Equatable {
        let url: String
        /// `small`, `default`, `large` or `xlarge`.
        let size: String?
    }

    /// A struct can't hold itself, so a related entity carries only its name.
    struct Related: Decodable, Sendable, Equatable { let entity: Named }
    struct Named: Decodable, Sendable, Equatable { let uri: String?; let decorations: NameOnly? }
    struct NameOnly: Decodable, Sendable, Equatable { let identity: Identity? }

    struct Playback: Decodable, Sendable, Equatable {
        let durationMs: Int?
        enum CodingKeys: String, CodingKey { case durationMs = "duration_ms" }
    }

    struct Ignored: Decodable, Sendable, Equatable {
        init(from decoder: any Decoder) throws {}
    }

    struct QueueEntry: Decodable, Sendable, Equatable {
        let uid: String?
        /// `context`, `queue` or `autoplay`.
        let source: String
        let item: Entity
    }

    struct ItemMessage: Decodable { let item: Entity? }
    struct ContextMessage: Decodable { let context: Entity? }
    struct QueueMessage: Decodable { let upcoming: [QueueEntry]? }
    struct StatusMessage: Decodable { let status: String }
    struct PositionMessage: Decodable { let position: Position }
    struct VolumeMessage: Decodable { let volume: Int }
    struct ResultMessage: Decodable { let command: String }
    struct ErrorMessage: Decodable { let message: String }

    struct DeviceMessage: Decodable {
        let isActive: Bool
        enum CodingKeys: String, CodingKey { case isActive = "is_active" }
    }
}
