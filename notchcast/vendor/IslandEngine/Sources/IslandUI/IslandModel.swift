import IslandCore
import Observation
import SwiftUI

/// What an island's views read from the nearest model, whatever its content type.
@MainActor
protocol IslandContext: AnyObject, Sendable {
    var clock: any IslandClock { get }
    var metrics: IslandMetrics { get }
    var motion: IslandMotion { get }
    var reducedMotion: ReducedMotionSetting { get }
    var recorder: FrameRecorder? { get }
}

/// Owns the activity stack and its clock. Put one in the environment with `islandModel(_:)`; views
/// read it with `@Environment(IslandModel<Content>.self)`.
@MainActor
@Observable
public final class IslandModel<Content>: SequenceIsland, IslandContext {
    /// The stack the island draws.
    @ObservationIgnored public let store: IslandStore<Content>
    /// The island's time, read once.
    @ObservationIgnored public let clock: any IslandClock
    /// Frame-exact control of the island, when created with `devtools` and no injected clock.
    @ObservationIgnored public let devtools: IslandDevtools<Content>?
    /// Frame timings, recorded only with devtools.
    @ObservationIgnored public let recorder: FrameRecorder?
    public var metrics: IslandMetrics
    public var motion: IslandMotion
    public var reducedMotion: ReducedMotionSetting
    private var observedSnapshot: IslandSnapshot<Content>
    /// The current stack, including changes inside an unfinished batch.
    public var snapshot: IslandSnapshot<Content> {
        _ = observedSnapshot
        return store.snapshot
    }

    @ObservationIgnored let frameSource: DisplayLinkFrameSource?
    @ObservationIgnored private var unsubscribe: Cancel?
    package var recordCall: (@MainActor (IslandStoreCall<Content>) -> Void)? {
        get { store.recordCall }
        set { store.recordCall = newValue }
    }

    /// A model on `clock`, or on the display's refresh when nil. `devtools` names the sequences
    /// `devtools.play` can run.
    public init(
        clock: (any IslandClock)? = nil, devtools: DevtoolsOptions<Content>? = nil, metrics: IslandMetrics = .standard,
        motion: IslandMotion = .standard, reducedMotion: ReducedMotionSetting = .user
    ) {
        let source = clock == nil ? DisplayLinkFrameSource() : nil
        let own = source.map { FrameClock(frameSource: $0) }
        let resolved: any IslandClock = clock ?? own!
        frameSource = source
        self.clock = resolved
        self.metrics = metrics
        self.motion = motion
        self.reducedMotion = reducedMotion
        let recorder = devtools == nil ? nil : FrameRecorder()
        self.recorder = recorder
        var read: (@MainActor () -> IslandMotion)?
        let store = IslandStore<Content>(clock: resolved) { read?() ?? .standard }
        self.store = store
        observedSnapshot = store.snapshot
        if let devtools, let own, let recorder {
            self.devtools = IslandDevtools(clock: own, store: store, recorder: recorder, options: devtools)
        } else {
            self.devtools = nil
        }
        read = { [weak self] in self?.motion ?? .standard }
        unsubscribe = store.subscribe { [weak self] in self?.storeChanged() }
    }

    isolated deinit {
        unsubscribe?()
    }

    /// Running activities, primary first, including grouped ones waiting hidden.
    public var activities: [Activity<Content>] { snapshot.activities }

    /// What the island shows right now.
    public var presentation: PresentationKind { deriveScene(snapshot).presentation.kind }

    /// Starts an activity, or updates it if the id already runs.
    @discardableResult
    public func start(_ options: ActivityOptions<Content>) -> ActivityHandle<Content> {
        let id = options.id
        store.batch { _ = store.start(options) }
        return ActivityHandle(id: id, update: { self.update(id, with: $0) }, end: { self.end(id) })
    }

    public func update(_ id: String, with update: ActivityUpdate<Content>) {
        store.batch { store.update(id, with: update) }
    }

    /// Removes the activity with `id`, with the system dismiss motion.
    public func end(_ id: String) {
        store.batch { store.end(id) }
    }

    /// Expands the activity with `id`, or the primary activity when nil.
    public func expand(_ id: String?) {
        store.batch { store.expand(id) }
    }

    public func collapse() {
        store.batch { store.collapse() }
    }

    /// Holds the pill, or the detached bubble, down.
    public func press(_ target: PressTarget) {
        store.batch { store.press(target) }
    }

    /// Lets go of a held press; a release before the long-press is decided is a tap.
    public func release() {
        release(cancel: false)
    }

    /// Lets go of a held press; with `cancel` it never counts as a tap.
    public func release(cancel: Bool) {
        store.batch { store.release(cancel: cancel) }
    }

    /// Runs `body` as one change: the island redraws once at its end, as one render would.
    @discardableResult
    public func batch<Result>(_ body: () throws -> Result) rethrows -> Result {
        try store.batch(body)
    }

    private func storeChanged() {
        observedSnapshot = store.snapshot
    }
}

/// Posts what an island announces to assistive tech; tests swap it to read the announcements.
final class IslandAnnouncer: Sendable {
    static let system = IslandAnnouncer { AccessibilityNotification.Announcement($0).post() }

    let post: @MainActor @Sendable (String) -> Void

    init(_ post: @escaping @MainActor @Sendable (String) -> Void) {
        self.post = post
    }
}

extension EnvironmentValues {
    @Entry var islandContext: (any IslandContext)? = nil
    @Entry var islandReducedMotionSetting: ReducedMotionSetting = .user
    @Entry var islandAnnouncer: IslandAnnouncer = .system
    /// The slot this content draws in, so a part can draw differently in a bubble; nil outside one.
    @Entry public var islandSlot: SlotName? = nil

    /// The clock island content animates on: the nearest model's, else the shared one.
    @MainActor public var islandClock: any IslandClock {
        islandContext?.clock ?? defaultClock()
    }

    /// Whether islands here run reduced motion: the model's setting resolved against the system's.
    public var islandReducedMotion: Bool {
        islandReducedMotionSetting.resolved(system: accessibilityReduceMotion)
    }
}

extension View {
    /// Makes `model` the island model for this view and its descendants.
    public func islandModel<Content>(_ model: IslandModel<Content>) -> some View {
        modifier(ModelEnvironment(model: model))
    }
}

private struct ModelEnvironment<IslandContent>: ViewModifier {
    let model: IslandModel<IslandContent>

    func body(content: Content) -> some View {
        content.environment(model).environment(\.islandContext, model)
            .environment(\.islandReducedMotionSetting, model.reducedMotion)
            .onPreferenceChange(IslandActivityCommits.self) { commits in
                MainActor.assumeIsolated {
                    for commit in commits where commit.model == ObjectIdentifier(model) { commit.run() }
                }
            }
    }
}

@MainActor private var sharedClock: FrameClock?

/// The clock islands use when nothing supplies one, shared: the main display's refresh.
@MainActor
public func defaultClock() -> FrameClock {
    if let sharedClock { return sharedClock }
    let clock = FrameClock(frameSource: DisplayLinkFrameSource())
    sharedClock = clock
    return clock
}
