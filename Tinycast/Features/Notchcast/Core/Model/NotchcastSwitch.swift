import Foundation

/// A permission a switch needs before its module can do anything.
enum NotchcastGrant: String, CaseIterable, Sendable {
    case accessibility
    case screenRecording
    case inputMonitoring
}

/// One user-facing feature. `id` is the persisted preference key, so it is frozen once shipped.
struct NotchcastSwitch: Sendable, Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let category: NotchcastCategory
    var defaultEnabled = false
    /// Switch ids, possibly another add-on's; an id no add-on declares counts as off.
    var dependencies: [String] = []
    var requiredGrants: Set<NotchcastGrant> = []
}
