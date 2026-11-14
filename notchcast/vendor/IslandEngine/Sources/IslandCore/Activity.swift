/// Content for the compact presentation. A slot that is absent shows nothing.
public struct CompactContent<Content> {
    /// Left of the sensor.
    public var leading: Content?
    /// Right of the sensor.
    public var trailing: Content?

    public init(leading: Content? = nil, trailing: Content? = nil) {
        self.leading = leading
        self.trailing = trailing
    }
}

extension CompactContent: Sendable where Content: Sendable {}
extension CompactContent: Equatable where Content: Equatable {}

/// Content for the expanded presentation. A slot that is absent shows nothing.
public struct ExpandedContent<Content> {
    /// Top left, beside the sensor.
    public var leading: Content?
    /// Top right, beside the sensor.
    public var trailing: Content?
    /// Between leading and trailing, below the sensor.
    public var center: Content?
    /// Full width under the top row.
    public var bottom: Content?

    public init(
        leading: Content? = nil,
        trailing: Content? = nil,
        center: Content? = nil,
        bottom: Content? = nil
    ) {
        self.leading = leading
        self.trailing = trailing
        self.center = center
        self.bottom = bottom
    }
}

extension ExpandedContent: Sendable where Content: Sendable {}
extension ExpandedContent: Equatable where Content: Equatable {}

/// Everything an activity can show. Each presentation falls back to empty slots.
public struct ActivityContent<Content> {
    /// Shown when this is the only activity.
    public var compact: CompactContent<Content>?
    /// Shown when two activities run and their compact content does not fit side by side.
    public var minimal: Content?
    /// Shown on long-press, `expand()`, or an alerting update.
    public var expanded: ExpandedContent<Content>?

    public init(
        compact: CompactContent<Content>? = nil,
        minimal: Content? = nil,
        expanded: ExpandedContent<Content>? = nil
    ) {
        self.compact = compact
        self.minimal = minimal
        self.expanded = expanded
    }
}

extension ActivityContent: Sendable where Content: Sendable {}
extension ActivityContent: Equatable where Content: Equatable {}

/// The two compact contents a minimal presentation can show side by side.
public struct MinimalSplit<Content> {
    /// The compact content of the activity attached to the pill.
    public var attached: CompactContent<Content>
    /// The compact content of the activity in the detached bubble.
    public var detached: CompactContent<Content>

    public init(attached: CompactContent<Content>, detached: CompactContent<Content>) {
        self.attached = attached
        self.detached = detached
    }
}

extension MinimalSplit: Sendable where Content: Sendable {}
extension MinimalSplit: Equatable where Content: Equatable {}

/// What the island shows, following ActivityKit's presentations, with the content it carries.
public enum IslandPresentation<Content> {
    /// The resting pill, no activity.
    case idle
    /// One activity, content on either side of the sensor area.
    case compact(CompactContent<Content>)
    /// Two activities: one attached to the pill, the other in a detached bubble.
    case minimal(attached: Content?, detached: Content?, split: MinimalSplit<Content>?)
    /// One activity, full width, with four regions.
    case expanded(ExpandedContent<Content>)

    /// Which presentation this is, without its content.
    public var kind: PresentationKind {
        switch self {
        case .idle: .idle
        case .compact: .compact
        case .minimal: .minimal
        case .expanded: .expanded
        }
    }
}

extension IslandPresentation: Sendable where Content: Sendable {}
extension IslandPresentation: Equatable where Content: Equatable {}

/// A change to one slot of an update: leave it, replace it, or empty it.
public enum Change<Value> {
    /// Keeps what the slot holds.
    case keep
    /// Replaces what the slot holds.
    case set(Value)
    /// Empties the slot.
    case clear

    /// Whether the update touches the slot at all.
    public var isGiven: Bool {
        if case .keep = self { false } else { true }
    }

    /// The slot's value once the change is applied to `current`.
    public func applied(to current: Value?) -> Value? {
        switch self {
        case .keep: current
        case .set(let value): value
        case .clear: nil
        }
    }
}

extension Change: Sendable where Value: Sendable {}
extension Change: Equatable where Value: Equatable {}

/// A partial change to compact content. A slot given replaces the old one; the other is kept.
public struct CompactChange<Content> {
    /// The change to the leading slot.
    public var leading: Change<Content>
    /// The change to the trailing slot.
    public var trailing: Change<Content>

    public init(leading: Change<Content> = .keep, trailing: Change<Content> = .keep) {
        self.leading = leading
        self.trailing = trailing
    }

    /// Compact content with every slot that has a value given as a replacement.
    public init(_ content: CompactContent<Content>) {
        leading = content.leading.map { .set($0) } ?? .keep
        trailing = content.trailing.map { .set($0) } ?? .keep
    }

    /// `content` with the change applied slot by slot.
    public func applied(to content: CompactContent<Content>) -> CompactContent<Content> {
        CompactContent(leading: leading.applied(to: content.leading), trailing: trailing.applied(to: content.trailing))
    }
}

extension CompactChange: Sendable where Content: Sendable {}
extension CompactChange: Equatable where Content: Equatable {}

/// A partial change to expanded content. A region given replaces the old one; the others are kept.
public struct ExpandedChange<Content> {
    /// The change to the leading region.
    public var leading: Change<Content>
    /// The change to the trailing region.
    public var trailing: Change<Content>
    /// The change to the center region.
    public var center: Change<Content>
    /// The change to the bottom region.
    public var bottom: Change<Content>

    public init(
        leading: Change<Content> = .keep,
        trailing: Change<Content> = .keep,
        center: Change<Content> = .keep,
        bottom: Change<Content> = .keep
    ) {
        self.leading = leading
        self.trailing = trailing
        self.center = center
        self.bottom = bottom
    }

    /// Expanded content with every region that has a value given as a replacement.
    public init(_ content: ExpandedContent<Content>) {
        leading = content.leading.map { .set($0) } ?? .keep
        trailing = content.trailing.map { .set($0) } ?? .keep
        center = content.center.map { .set($0) } ?? .keep
        bottom = content.bottom.map { .set($0) } ?? .keep
    }

    /// `content` with the change applied region by region.
    public func applied(to content: ExpandedContent<Content>) -> ExpandedContent<Content> {
        ExpandedContent(
            leading: leading.applied(to: content.leading),
            trailing: trailing.applied(to: content.trailing),
            center: center.applied(to: content.center),
            bottom: bottom.applied(to: content.bottom)
        )
    }
}

extension ExpandedChange: Sendable where Content: Sendable {}
extension ExpandedChange: Equatable where Content: Equatable {}

/// What starting an activity takes. Starting an id that already runs updates it instead.
public struct ActivityOptions<Content> {
    /// Unique id.
    public var id: String
    /// Shown when this is the only activity.
    public var compact: CompactContent<Content>?
    /// Shown when two activities run and their compact content does not fit side by side.
    public var minimal: Content?
    /// Shown on long-press, `expand()`, or an alerting update.
    public var expanded: ExpandedContent<Content>?
    /// Spoken by screen readers when the activity starts or changes. Defaults to the id.
    public var label: String?
    /// Higher priority takes the primary slot; ties go to the first started. Defaults to 0.
    public var priority: Double?
    /// Called on a tap, a press shorter than the long-press.
    public var onPress: (@MainActor () -> Void)?
    /// Starts with an alert: expands briefly, then settles to compact.
    public var alert: Bool
    /// Activities of one group show one at a time, the first started first; an alert hands over.
    public var group: String?

    public init(
        id: String,
        compact: CompactContent<Content>? = nil,
        minimal: Content? = nil,
        expanded: ExpandedContent<Content>? = nil,
        label: String? = nil,
        priority: Double? = nil,
        onPress: (@MainActor () -> Void)? = nil,
        alert: Bool = false,
        group: String? = nil
    ) {
        self.id = id
        self.compact = compact
        self.minimal = minimal
        self.expanded = expanded
        self.label = label
        self.priority = priority
        self.onPress = onPress
        self.alert = alert
        self.group = group
    }
}

extension ActivityOptions: Sendable where Content: Sendable {}

/// How an update changes the layer that shows an activity's content.
public enum ActivityTransition: String, Sendable, CaseIterable {
    /// Changes content in place, as a number ticks or a bar moves.
    case update
    /// Replaces the layer with a blur and fade, for content that is different, not just newer.
    case crossfade
}

/// A partial update. Nested content merges, so a compact update can replace one slot only.
public struct ActivityUpdate<Content> {
    /// Changes the compact slots given.
    public var compact: CompactChange<Content>?
    /// Replaces, empties or keeps the minimal content.
    public var minimal: Change<Content>
    /// Changes the expanded regions given.
    public var expanded: ExpandedChange<Content>?
    /// Replaces the screen reader label.
    public var label: String?
    /// Replaces the priority.
    public var priority: Double?
    /// Replaces, empties or keeps the tap handler.
    public var onPress: Change<@MainActor () -> Void>
    /// Expands briefly to draw attention, applying the content change once the island is open.
    public var alert: Bool
    /// How the content layer changes.
    public var transition: ActivityTransition
    // Upstream forwards group in content updates even though updates never change the group.
    package var forwardedGroup: String?

    public init(
        compact: CompactChange<Content>? = nil,
        minimal: Change<Content> = .keep,
        expanded: ExpandedChange<Content>? = nil,
        label: String? = nil,
        priority: Double? = nil,
        onPress: Change<@MainActor () -> Void> = .keep,
        alert: Bool = false,
        transition: ActivityTransition = .update
    ) {
        self.compact = compact
        self.minimal = minimal
        self.expanded = expanded
        self.label = label
        self.priority = priority
        self.onPress = onPress
        self.alert = alert
        self.transition = transition
    }

    /// The update that starting an id that already runs applies: every value given replaces.
    public init(_ options: ActivityOptions<Content>) {
        self.init(
            compact: options.compact.map(CompactChange.init),
            minimal: options.minimal.map { .set($0) } ?? .keep,
            expanded: options.expanded.map(ExpandedChange.init),
            label: options.label,
            priority: options.priority,
            onPress: options.onPress.map { .set($0) } ?? .keep,
            alert: options.alert
        )
        forwardedGroup = options.group
    }
}

extension ActivityUpdate: Sendable where Content: Sendable {}

/// What `start` returns: the id, and the two things an activity can be told afterwards.
@MainActor
public struct ActivityHandle<Content> {
    /// The id of the activity.
    public let id: String
    private let updater: @MainActor (ActivityUpdate<Content>) -> Void
    private let ender: @MainActor () -> Void

    public init(
        id: String,
        update: @escaping @MainActor (ActivityUpdate<Content>) -> Void,
        end: @escaping @MainActor () -> Void
    ) {
        self.id = id
        updater = update
        ender = end
    }

    /// Applies a partial update to the activity.
    public func update(_ update: ActivityUpdate<Content>) {
        updater(update)
    }

    /// Removes the activity with the system dismiss motion.
    public func end() {
        ender()
    }
}

/// An activity as the island holds it.
public struct Activity<Content> {
    /// Unique id.
    public var id: String
    /// What screen readers speak.
    public var label: String
    /// Higher priority takes the primary slot.
    public var priority: Double
    /// Start order, used to break priority ties.
    public var order: Int
    /// What the activity shows in each presentation.
    public var content: ActivityContent<Content>
    /// Called on a tap.
    public var onPress: (@MainActor () -> Void)?
    /// Bumped by crossfade updates: a new revision replaces the content layer.
    public var revision: Int
    /// The group it shows in turn with, if any.
    public var group: String?

    public init(
        id: String,
        label: String,
        priority: Double,
        order: Int,
        content: ActivityContent<Content>,
        onPress: (@MainActor () -> Void)? = nil,
        revision: Int = 0,
        group: String? = nil
    ) {
        self.id = id
        self.label = label
        self.priority = priority
        self.order = order
        self.content = content
        self.onPress = onPress
        self.revision = revision
        self.group = group
    }
}

extension Activity: Sendable where Content: Sendable {}

/// Why the island is expanded. Alerts collapse by themselves; user expansions wait for a press outside.
public enum ExpandReason: String, Sendable, CaseIterable {
    /// A long-press or an explicit `expand()`.
    case user
    /// An alert, which returns to compact on its own.
    case alert
}

/// What activities can be driven through: start, update, end, expand and collapse.
@MainActor
public protocol IslandApi<Content>: AnyObject {
    associatedtype Content

    /// Starts an activity, or updates it if the id already runs.
    @discardableResult
    func start(_ options: ActivityOptions<Content>) -> ActivityHandle<Content>
    /// Applies a partial update to the activity with `id`.
    func update(_ id: String, with update: ActivityUpdate<Content>)
    /// Removes the activity with `id`.
    func end(_ id: String)
    /// Expands the activity with `id`, or the primary activity when `id` is nil.
    func expand(_ id: String?)
    /// Collapses an expanded island.
    func collapse()
    /// Running activities, primary first, including grouped ones waiting hidden.
    var activities: [Activity<Content>] { get }
    /// What the island shows right now.
    var presentation: PresentationKind { get }
}

/// What sequence events can drive: the activity API plus presses.
@MainActor
public protocol SequenceIsland<Content>: IslandApi {
    /// Holds the pill, or the detached bubble, down.
    func press(_ target: PressTarget)
    /// Lets go of a held press.
    func release()
}

extension IslandApi {
    /// Expands the primary activity.
    public func expand() {
        expand(nil)
    }
}

extension SequenceIsland {
    /// Holds the pill down.
    public func press() {
        press(.pill)
    }
}

/// A scripted run for captures: build the starting state instantly, then fire events at times.
public struct IslandSequence<Content> {
    /// An event, fired `at` milliseconds from the start.
    public struct Event {
        /// Milliseconds from the start.
        public var at: Double
        /// What the event does.
        public var run: @MainActor (any SequenceIsland<Content>) -> Void

        public init(at: Double, run: @escaping @MainActor (any SequenceIsland<Content>) -> Void) {
            self.at = at
            self.run = run
        }
    }

    /// Builds the starting state with no animation, before time 0.
    public var setup: (@MainActor (any SequenceIsland<Content>) -> Void)?
    /// Events in order of time.
    public var events: [Event]
    /// Total length in milliseconds, so a capture knows when to stop.
    public var duration: Double

    public init(
        setup: (@MainActor (any SequenceIsland<Content>) -> Void)? = nil,
        events: [Event],
        duration: Double
    ) {
        self.setup = setup
        self.events = events
        self.duration = duration
    }
}

/// Whether the system's reduced-motion setting applies.
public enum ReducedMotionSetting: String, Sendable, CaseIterable {
    /// Follows the system setting.
    case user
    /// Always reduces motion.
    case always
    /// Never reduces motion.
    case never
}
