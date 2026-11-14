/// What the island shows, following ActivityKit's presentations.
public enum PresentationKind: String, CaseIterable, Codable, Sendable {
    /// The resting pill, no activity.
    case idle
    /// One activity, content on either side of the sensor area.
    case compact
    /// Two activities: one attached to the pill, the other in a detached bubble.
    case minimal
    /// One activity, full width, with four regions.
    case expanded
}
