import Foundation
import Observation

extension ContentScene {
    /// The scene the island root hands its surface for `snapshot`, drawn under `scene`.
    public init<Content>(_ scene: IslandScene<Content>, snapshot: IslandSnapshot<Content>, keyline: Double) {
        var hasBottom = false
        if case .expanded(let content) = scene.presentation { hasBottom = content.bottom != nil }
        self.init(
            key: scene.contentKey, kind: scene.presentation.kind,
            change: Change(id: snapshot.changeId, at: snapshot.changedAt, instant: snapshot.instant),
            pressed: snapshot.pressed.map { $0 == .pill ? .pill : .bubble }, joining: snapshot.joining,
            activityId: scene.primary?.id, alerting: snapshot.expanded?.reason == .alert,
            handingOff: snapshot.handoff != nil,
            // Upstream's empty minimal content is null rather than undefined, so the slot always mounts.
            hasDetached: scene.presentation.kind == .minimal, hasBottom: hasBottom, keyline: keyline)
    }
}

/// One call the surface made on its stage, for tests that hold it to upstream's order.
enum SurfaceCall: Equatable {
    case retarget(t: Double, drew: Bool)
    case tick(t: Double)
}

/// Connects a store, or a controlled presentation, to a content stage: retargets after every
/// change and draws frames until rest.
@MainActor
@Observable
public final class IslandSurface<Content> {
    /// Where the surface's scenes come from.
    private enum Source {
        case store(IslandStore<Content>)
        case controlled(presentation: IslandPresentation<Content>, contentKey: String, pressed: Bool)
    }

    /// The layers, shadow and clip as last drawn.
    public private(set) var stage: ContentStage
    /// Clock time (ms) of the last drawn frame.
    public private(set) var time: Double
    /// Each mounted layer's presentation, by layer key.
    public private(set) var presentations: StringMap<IslandPresentation<Content>> = [:]
    /// The container's width the island is centred in.
    public private(set) var stageWidth: Double
    /// The key of the layer on show.
    public private(set) var contentKey = ""

    /// Whether springs give way to short crossfades. Setting it retargets.
    public var reduced: Bool {
        get { stage.reduced }
        set {
            guard newValue != stage.reduced else { return }
            stage.reduced = newValue
            retarget()
        }
    }

    /// The keyline's alpha over the page; 0 draws none. Setting it retargets.
    @ObservationIgnored public var keyline: Double {
        didSet { if keyline != oldValue { retarget() } }
    }

    /// Records each animating frame's timing, when set.
    @ObservationIgnored public var recorder: FrameRecorder?

    @ObservationIgnored private var source: Source
    @ObservationIgnored private let clock: any IslandClock
    @ObservationIgnored private let measure: @MainActor (IslandPresentation<Content>, Double) -> ContentMeasures
    @ObservationIgnored private let wall: @MainActor () -> Double
    @ObservationIgnored private var unsubscribe: Cancel?
    @ObservationIgnored private var stopFrames: Cancel?
    @ObservationIgnored private var batching = 0
    @ObservationIgnored private var changed = false
    @ObservationIgnored var trace: (@MainActor (SurfaceCall) -> Void)?
    /// Called with the clock time (ms) and the transition each time a retarget moves the shape.
    @_spi(Lab) @ObservationIgnored public var onShapeTransition: (@MainActor (Double, ShapeTransition) -> Void)?

    /// A surface drawing `store` on `clock`; `measure` lays out the current presentation's content
    /// in a container as wide as its second argument.
    public convenience init(
        store: IslandStore<Content>, clock: any IslandClock, metrics: IslandMetrics, motion: IslandMotion,
        dpr: Double, reduced: Bool, keyline: Double, stageWidth: Double,
        measure: @escaping @MainActor (IslandPresentation<Content>, Double) -> ContentMeasures
    ) {
        self.init(
            source: .store(store), clock: clock, metrics: metrics, motion: motion, dpr: dpr, reduced: reduced,
            keyline: keyline, stageWidth: stageWidth, measure: measure)
        unsubscribe = store.subscribeToPresentation { [weak self] in self?.storeChanged() }
    }

    /// A surface whose content measures the same at any container width.
    public convenience init(
        store: IslandStore<Content>, clock: any IslandClock, metrics: IslandMetrics, motion: IslandMotion,
        dpr: Double, reduced: Bool, keyline: Double, stageWidth: Double,
        measure: @escaping @MainActor (IslandPresentation<Content>) -> ContentMeasures
    ) {
        self.init(
            store: store, clock: clock, metrics: metrics, motion: motion, dpr: dpr, reduced: reduced,
            keyline: keyline, stageWidth: stageWidth, measure: { presentation, _ in measure(presentation) })
    }

    /// A surface showing one controlled presentation, with no activity stack; `show` changes it.
    public convenience init(
        presentation: IslandPresentation<Content>, contentKey: String? = nil, pressed: Bool = false,
        clock: any IslandClock, metrics: IslandMetrics, motion: IslandMotion, dpr: Double, reduced: Bool,
        keyline: Double, stageWidth: Double,
        measure: @escaping @MainActor (IslandPresentation<Content>, Double) -> ContentMeasures
    ) {
        self.init(
            source: .controlled(
                presentation: presentation, contentKey: contentKey ?? presentation.kind.rawValue, pressed: pressed),
            clock: clock, metrics: metrics, motion: motion, dpr: dpr, reduced: reduced, keyline: keyline,
            stageWidth: stageWidth, measure: measure)
    }

    private init(
        source: Source, clock: any IslandClock, metrics: IslandMetrics, motion: IslandMotion, dpr: Double,
        reduced: Bool, keyline: Double, stageWidth: Double,
        measure: @escaping @MainActor (IslandPresentation<Content>, Double) -> ContentMeasures
    ) {
        self.source = source
        self.clock = clock
        self.keyline = keyline
        self.measure = measure
        self.stageWidth = stageWidth
        wall = { ProcessInfo.processInfo.systemUptime * 1000 }
        stage = ContentStage(metrics: metrics, motion: motion, dpr: dpr, reduced: reduced)
        time = clock.now()
        retarget()
    }

    isolated deinit {
        unsubscribe?()
        stopFrames?()
    }

    /// The shape as last drawn.
    public var shape: FrameGeometry { stage.shape(at: time) }

    /// Shows a new controlled presentation; a new `contentKey` crossfades, the same one updates in place.
    /// A store-driven surface ignores it.
    public func show(_ presentation: IslandPresentation<Content>, contentKey: String? = nil, pressed: Bool = false) {
        guard case .controlled = source else { return }
        source = .controlled(
            presentation: presentation, contentKey: contentKey ?? presentation.kind.rawValue, pressed: pressed)
        retarget()
    }

    /// Centres the island in a container `width` wide.
    public func resize(stageWidth width: Double) {
        guard width != stageWidth else { return }
        stageWidth = width
        retarget()
    }

    /// Tells the surface its current content changed size outside a store change.
    public func contentResized() {
        retarget()
    }

    /// Runs `body` as one change: however often the store changes in it, the surface retargets once.
    public func batch(_ body: () -> Void) {
        batching += 1
        body()
        batching -= 1
        guard batching == 0, changed else { return }
        changed = false
        retarget()
    }

    private func storeChanged() {
        if batching > 0 { changed = true } else { retarget() }
    }

    private func scene() -> (presentation: IslandPresentation<Content>, scene: ContentScene) {
        switch source {
        case .store(let store):
            let snapshot = store.snapshot
            let scene = deriveScene(snapshot)
            return (scene.presentation, ContentScene(scene, snapshot: snapshot, keyline: keyline))
        case .controlled(let presentation, let key, let pressed):
            var hasDetached = false
            var hasBottom = false
            if case .minimal(_, let detached, _) = presentation { hasDetached = detached != nil }
            if case .expanded(let content) = presentation { hasBottom = content.bottom != nil }
            return (
                presentation,
                ContentScene(
                    key: key, kind: presentation.kind, change: nil, pressed: pressed ? .pill : nil,
                    pressStyle: .squish, hasDetached: hasDetached, hasBottom: hasBottom, keyline: keyline)
            )
        }
    }

    private func retarget() {
        let (presentation, scene) = scene()
        presentations[scene.key] = presentation
        contentKey = scene.key
        let now = clock.now()
        let drew = stage.retarget(
            scene: scene, measures: measure(presentation, stageWidth), stageWidth: stageWidth, now: now)
        let mounted = StringSet(stage.layers.map(\.key))
        presentations = presentations.filter { mounted.contains($0.key) }
        time = now
        trace?(.retarget(t: now, drew: drew))
        if let transition = stage.shapeTransition { onShapeTransition?(now, transition) }
        if drew { run() }
    }

    private func run() {
        guard stopFrames == nil else { return }
        stopFrames = clock.onFrame { [weak self] now in self?.tick(now) }
    }

    private func tick(_ now: Double) {
        trace?(.tick(t: now))
        let started = wall()
        let rest = stage.advance(now: now)
        recorder?.record(startedAt: started, work: wall() - started)
        time = now
        if rest {
            stopFrames?()
            stopFrames = nil
            recorder?.breakRun()
        }
        if stage.unmounting { retarget() }
    }
}
