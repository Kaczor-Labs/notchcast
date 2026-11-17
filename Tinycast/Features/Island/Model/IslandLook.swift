import Foundation
import Observation

/// How the island paints on one display: the black it always had, or graphite glass.
enum IslandLook: String, CaseIterable, Sendable {
    case black, frosted

    /// Black exists to blend with notch hardware, so only a notch keeps it unless chosen.
    static func standard(hasNotch: Bool) -> IslandLook { hasNotch ? .black : .frosted }
}

/// A connected display as the Look settings list it; `uuid` is nil when CoreGraphics gives none.
struct IslandLookDisplay: Identifiable, Equatable, Sendable {
    let displayID: UInt32
    let uuid: String?
    let name: String
    let hasNotch: Bool

    var id: UInt32 { displayID }
}

/// Explicit per-display looks, keyed by display UUID so a choice outlives a replug or a restart.
@MainActor
@Observable
final class IslandLookStore {
    nonisolated static let key = "islandLooks"
    @ObservationIgnored private let defaults: UserDefaults
    private(set) var choices: [String: IslandLook]
    /// The look of the display the palette opened on, read under the palette root.
    var palette = IslandLook.black
    /// Refreshed by the island on every screen change, so Settings follows plug and unplug.
    var displays: [IslandLookDisplay] = []

    init(defaults: UserDefaults) {
        self.defaults = defaults
        choices = Self.decode(defaults.object(forKey: Self.key))
    }

    /// Anything unreadable counts as never chosen, so bad data falls back to the default rule.
    nonisolated static func decode(_ stored: Any?) -> [String: IslandLook] {
        guard let raw = stored as? [String: Any] else { return [:] }
        return raw.compactMapValues { ($0 as? String).flatMap(IslandLook.init(rawValue:)) }
    }

    func look(uuid: String?, hasNotch: Bool) -> IslandLook {
        uuid.flatMap { choices[$0] } ?? .standard(hasNotch: hasNotch)
    }

    func look(_ display: IslandLookDisplay) -> IslandLook { look(uuid: display.uuid, hasNotch: display.hasNotch) }

    /// A display without a UUID stores nothing and keeps the default rule.
    func set(_ look: IslandLook, uuid: String?) {
        guard let uuid, choices[uuid] != look else { return }
        choices[uuid] = look
        defaults.set(choices.mapValues(\.rawValue), forKey: Self.key)
    }
}
