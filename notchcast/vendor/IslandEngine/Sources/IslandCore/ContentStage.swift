import Foundation

/// What the island shows: the content layer's key and presentation, and the props that move it.
public struct ContentScene: Sendable, Equatable {
    /// A stamped presentation change: its id, clock time (ms) and whether it skips animation.
    public struct Change: Sendable, Equatable {
        public var id: Int
        public var at: Double
        public var instant: Bool

        /// A change with every field set.
        public init(id: Int, at: Double, instant: Bool) {
            self.id = id
            self.at = at
            self.instant = instant
        }
    }

    /// The content layer this scene shows; a new key brings a new layer.
    public var key: String
    public var kind: PresentationKind
    public var change: Change?
    public var pressed: PressedPart?
    /// How the pressed part answers: the stack's `swell`, or a controlled view's `squish`.
    public var pressStyle: PressStyle
    /// Clock time (ms) a minimal bubble joins the expanded shape, while one is joining.
    public var joining: Double?
    public var activityId: String?
    public var alerting: Bool
    public var handingOff: Bool
    /// Whether the minimal presentation has a detached slot.
    public var hasDetached: Bool
    /// Whether the expanded presentation has a bottom region.
    public var hasBottom: Bool
    /// The keyline's alpha over the page; 0 draws none.
    public var keyline: Double

    /// A scene with every field set.
    public init(
        key: String, kind: PresentationKind, change: Change?, pressed: PressedPart? = nil,
        pressStyle: PressStyle = .swell, joining: Double? = nil,
        activityId: String? = nil, alerting: Bool = false, handingOff: Bool = false, hasDetached: Bool = false,
        hasBottom: Bool = false, keyline: Double
    ) {
        self.key = key
        self.kind = kind
        self.change = change
        self.pressed = pressed
        self.pressStyle = pressStyle
        self.joining = joining
        self.activityId = activityId
        self.alerting = alerting
        self.handingOff = handingOff
        self.hasDetached = hasDetached
        self.hasBottom = hasBottom
        self.keyline = keyline
    }
}

/// The current layer's measured content, before it is held steady against earlier measures.
public struct ContentMeasures: Sendable, Equatable {
    public var leading: Double
    public var trailing: Double
    public var attached: Double
    public var detached: Double
    /// The split slots' widths; the detached trailing one is its natural width. Nil without them.
    public var split: ContentMeasure.Split?
    public var expandedHeight: Double
    /// Each expanded region's centre in the expanded slot, when it is laid out.
    public var regions: PerRegion<Vec>

    /// Measures with every field set.
    public init(
        leading: Double = 0, trailing: Double = 0, attached: Double = 0, detached: Double = 0,
        split: ContentMeasure.Split? = nil, expandedHeight: Double = 0, regions: PerRegion<Vec> = PerRegion()
    ) {
        self.leading = leading
        self.trailing = trailing
        self.attached = attached
        self.detached = detached
        self.split = split
        self.expandedHeight = expandedHeight
        self.regions = regions
    }
}

/// A slot's written visibility.
public enum SlotVisibility: Sendable, Equatable {
    case inherit
    case hidden
    case visible
}

/// A slot's compositing hint: `auto` once still, `moving` while it animates.
public enum SlotHint: Sendable, Equatable {
    case auto
    case moving
}

/// A slot's layout display.
public enum SlotDisplay: Sendable, Equatable {
    case flex
    case block
}

/// A slot's clip, in the slot's own points.
public enum SlotClip: Sendable, Equatable {
    case none
    /// The island's content clip, or the expanded clip following the content.
    case path(IslandPath)
    /// A band across a bubble slot, reaching `reach` left and to `right`.
    case band(reach: Double, top: Double, right: Double, bottom: Double)
    /// A band whose right end is a half-ellipse at `capX`.
    case cappedBand(reach: Double, top: Double, capX: Double, rx: Double, ry: Double, bottom: Double)
}

/// A slot's translation, then an optional lift and scale.
public struct SlotTransform: Sendable, Equatable {
    public var x: Double
    public var y: Double
    /// Points the slot is drawn above its place, or nil for none.
    public var lift: Double?
    public var sx: Double?
    public var sy: Double?

    /// A transform with every field set.
    public init(x: Double, y: Double, lift: Double? = nil, sx: Double? = nil, sy: Double? = nil) {
        self.x = x
        self.y = y
        self.lift = lift
        self.sx = sx
        self.sy = sy
    }
}

/// A blurred slot's wide part: a copy of it, blurred wider and added on top (`plus-lighter`), with the
/// slot's own transform and clip. On the expanded clip it is the copy of the whole clipped view.
public struct SlotEcho: Sendable, Equatable {
    public var opacity: Double
    /// The copy's blur in points, before the transform; 0 is no filter.
    public var blur: Double

    public init(opacity: Double, blur: Double) {
        self.opacity = opacity
        self.blur = blur
    }
}

/// What is written on one slot; nil fields were never written.
public struct SlotStyle: Sendable, Equatable {
    public var opacity: Double?
    /// The filter's blur in points; 0 is no filter.
    public var blur: Double?
    public var transform: SlotTransform?
    public var clip: SlotClip?
    public var visibility: SlotVisibility?
    public var willChange: SlotHint?
    /// The width a too-wide slot is cut to.
    public var maxWidth: Double?
    public var display: SlotDisplay?
    /// The copy drawing this frame's wide part of the blur, or nil for none.
    public var echo: SlotEcho?

    /// A style with every field set.
    public init(
        opacity: Double? = nil, blur: Double? = nil, transform: SlotTransform? = nil, clip: SlotClip? = nil,
        visibility: SlotVisibility? = nil, willChange: SlotHint? = nil, maxWidth: Double? = nil,
        display: SlotDisplay? = nil, echo: SlotEcho? = nil
    ) {
        self.opacity = opacity
        self.blur = blur
        self.transform = transform
        self.clip = clip
        self.visibility = visibility
        self.willChange = willChange
        self.maxWidth = maxWidth
        self.display = display
        self.echo = echo
    }
}

/// One mounted content layer: its key, its presentation and its slots' styles.
public struct ContentLayer: Sendable, Equatable {
    public var key: String
    public var kind: PresentationKind
    /// The layer's mounted slots and what is written on each.
    public var slots: [SlotName: SlotStyle]
}

/// The shadow's slopes and filter, and the keyline's opacity.
public struct ContentShadow: Sendable, Equatable {
    public var slope: Double
    public var tailSlope: Double
    public var filtered: Bool
    public var keyline: Double
}

/// A mounted layer's laid-out widths, held steady between measures.
struct LayerSize: Sendable {
    var leading: Double
    var trailing: Double
    var attached: Double
    var detached: Double
    var split: ContentMeasure.Split?
    var useSplit: Bool
    var regions: PerRegion<Vec>

    static let empty = LayerSize(
        leading: 0, trailing: 0, attached: 0, detached: 0, split: nil, useSplit: false, regions: PerRegion())
}

/// What the last drawn retarget aimed for.
struct LastRetarget: Sendable {
    var key: String?
    var kind: PresentationKind = .idle
    var changeId: Int?
    var width: Double = 0
    var target: ShapeTarget?
    var pressed: PressedPart?
    var joining: Double?
    var activityId: String?
    var alerting = false
    var handingOff = false
}

/// The island's content layers through every change: what each draws and when it leaves.
public struct ContentStage: Sendable {
    public let metrics: IslandMetrics
    public let motion: IslandMotion
    public let dpr: Double
    /// Whether springs give way to short crossfades; read on every retarget and frame.
    public var reduced: Bool
    /// The mounted layers: those leaving, then the current one.
    public internal(set) var layers: [ContentLayer] = []
    public internal(set) var shadow = ContentShadow(slope: 0, tailSlope: 0, filtered: false, keyline: 0)
    /// The island's content clip on the last drawn frame, or nil for none.
    public internal(set) var frameClip: IslandPath?

    /// The transition the last retarget moved the shape by, nil when it left the shape alone.
    @_spi(Lab) public internal(set) var shapeTransition: ShapeTransition?

    var anim: ShapeAnimation
    var last = LastRetarget()
    var scene: ContentScene?
    var stageWidth = 0.0
    var shown: (key: String, kind: PresentationKind)?
    var leaving: [(key: String, kind: PresentationKind)] = []
    var removals: [String] = []
    var presence: StringMap<AnimatedValue> = [:]
    var bubbleExits: StringMap<AnimatedValue> = [:]
    var bubbleEnters: StringMap<AnimatedValue> = [:]
    var trailingEnters: StringMap<AnimatedValue> = [:]
    var bubbleSettles: StringMap<AnimatedValue> = [:]
    var partSteps: StringMap<AnimatedValue> = [:]
    var leavingSlides: StringMap<AnimatedValue> = [:]
    var carries: StringMap<Carry> = [:]
    var rejoins: StringSet = []
    var cutting: StringSet = []
    var removing: StringSet = []
    var capHolds: StringMap<Double?> = [:]
    var looks: StringMap<LayerLook> = [:]
    var rests: StringMap<ShapeTarget> = [:]
    var widths: StringMap<LayerSize> = [:]
    var keylineDip: Double?

    /// A stage with no layers, its shape at rest idle.
    public init(metrics: IslandMetrics, motion: IslandMotion, dpr: Double, reduced: Bool) {
        self.metrics = metrics
        self.motion = motion
        self.dpr = dpr
        self.reduced = reduced
        anim = ShapeAnimation(
            target: ShapeTarget(.idle, measure: .empty, screenWidth: metrics.screen.width, metrics: metrics),
            metrics: metrics)
    }

    /// The shape at clock time `now` (ms), on the stage of the last retarget.
    public func shape(at now: Double) -> FrameGeometry {
        anim.frame(at: now / 1000, stageWidth: islandScreenWidth(containerWidth: stageWidth, metrics: metrics),
            metrics: metrics)
    }

    /// Whether a layer is done leaving and the next retarget unmounts it.
    public var unmounting: Bool { !removals.isEmpty }

    /// The keys of the layers leaving.
    var leavingKeys: [String] {
        guard let key = scene?.key else { return [] }
        return leaving.filter { !sameString($0.key, key) }.map(\.key)
    }

    /// Shows `scene` at clock time `now` (ms) on a stage `stageWidth` wide; true when it drew.
    public mutating func retarget(scene: ContentScene, measures: ContentMeasures, stageWidth: Double, now: Double)
        -> Bool
    {
        mount(scene, measures)
        self.stageWidth = stageWidth
        let drew = place(scene, measures, now: now)
        drop()
        return drew
    }

    /// Draws a frame at `now` (ms) and settles what came to rest; true once everything is at rest.
    public mutating func advance(now: Double) -> Bool {
        draw(now: now)
        let t = now / 1000
        var rest = anim.isAtRest(at: t)
        let leavingKeys = leavingKeys
        for key in presence.keys {
            let target = presence[key]!.target
            let at = target == 1 && !reduced ? t - (looks[key]?.lag ?? 0) : t
            let settled = presence[key]!.isAtRest(at: at)
            rest = rest && settled
            if carries[key]?.weight.isAtRest(at: t) == true {
                carries[key] = nil
            } else if carries[key] != nil {
                rest = false
            }
            if settled && carries[key] == nil && target == 0 && leavingKeys.contains(where: { sameString($0, key) }) && !removing.contains(key) {
                removing.insert(key)
                removals.append(key)
            }
        }
        for path in [\ContentStage.bubbleSettles, \.bubbleEnters, \.trailingEnters, \.bubbleExits, \.partSteps,
            \.leavingSlides]
        {
            for key in self[keyPath: path].keys {
                rest = self[keyPath: path][key]!.isAtRest(at: t) && rest
            }
        }
        if rest { draw(now: now, still: true) }
        return rest
    }

    /// Mounts the scene's layer and moves the one it replaces to the leaving layers.
    mutating func mount(_ scene: ContentScene, _ measures: ContentMeasures) {
        for key in removals { leaving.removeAll { sameString($0.key, key) } }
        removals = []
        if let was = shown, !sameString(was.key, scene.key) {
            leaving = leaving.filter { !sameString($0.key, scene.key) && !sameString($0.key, was.key) } + [was]
        }
        if !sameString(shown?.key, scene.key) { shown = (scene.key, scene.kind) }
        self.scene = scene
        var byKey: StringMap<ContentLayer> = [:]
        for layer in layers { byKey[layer.key] = layer }
        var mounted: [ContentLayer] = []
        for was in leaving where !sameString(was.key, scene.key) {
            mounted.append(byKey[was.key] ?? ContentLayer(key: was.key, kind: was.kind, slots: Self.mountStyles(
                was.kind, Self.slotNames(was.kind, hasDetached: false, hasBottom: false, hasSplit: false))))
        }
        var current = byKey[scene.key] ?? ContentLayer(key: scene.key, kind: scene.kind, slots: [:])
        current.kind = scene.kind
        let names = Self.slotNames(
            scene.kind, hasDetached: scene.hasDetached, hasBottom: scene.hasBottom, hasSplit: measures.split != nil)
        let fresh = Self.mountStyles(scene.kind, names.filter { current.slots[$0] == nil })
        current.slots = current.slots.filter { names.contains($0.key) }.merging(fresh) { old, _ in old }
        mounted.append(current)
        layers = mounted
    }

    /// The slots a layer of `kind` mounts.
    static func slotNames(_ kind: PresentationKind, hasDetached: Bool, hasBottom: Bool, hasSplit: Bool) -> [SlotName] {
        switch kind {
        case .idle:
            return [.root]
        case .compact:
            return [.root, .leading, .trailing]
        case .minimal:
            let split: [SlotName] = hasSplit
                ? [.splitAttachedLeading, .splitAttachedTrailing, .splitDetachedLeading, .splitDetachedTrailing] : []
            return [.root, .attached] + (hasDetached ? [.detached] : []) + split
        case .expanded:
            return [.root, .expandedClip, .expanded, .expandedLeading, .expandedCenter, .expandedTrailing]
                + (hasBottom ? [.expandedBottom] : [])
        }
    }

    /// The styles each slot is mounted with.
    static func mountStyles(_ kind: PresentationKind, _ names: [SlotName]) -> [SlotName: SlotStyle] {
        var styles: [SlotName: SlotStyle] = [:]
        for name in names {
            switch (kind, name) {
            case (_, .root), (.expanded, .expandedClip), (.expanded, .expandedLeading), (.expanded, .expandedTrailing),
                (.expanded, .expandedBottom):
                styles[name] = SlotStyle()
            case (.expanded, .expanded):
                styles[name] = SlotStyle(willChange: .moving, display: .block)
            case (.expanded, .expandedCenter):
                styles[name] = SlotStyle(display: .flex)
            default:
                styles[name] = SlotStyle(willChange: .moving, display: .flex)
            }
        }
        return styles
    }

    /// Forgets every layer that is no longer mounted.
    mutating func drop() {
        let keep = StringSet(layers.map(\.key))
        presence = presence.filter { keep.contains($0.key) }
        bubbleExits = bubbleExits.filter { keep.contains($0.key) }
        bubbleEnters = bubbleEnters.filter { keep.contains($0.key) }
        trailingEnters = trailingEnters.filter { keep.contains($0.key) }
        bubbleSettles = bubbleSettles.filter { keep.contains($0.key) }
        partSteps = partSteps.filter { keep.contains($0.key) }
        leavingSlides = leavingSlides.filter { keep.contains($0.key) }
        carries = carries.filter { keep.contains($0.key) }
        rejoins = rejoins.filter { keep.contains($0) }
        cutting = cutting.filter { keep.contains($0) }
        capHolds = capHolds.filter { keep.contains($0.key) }
        looks = looks.filter { keep.contains($0.key) }
        rests = rests.filter { keep.contains($0.key) }
        removing = removing.filter { keep.contains($0) }
    }

    /// Writes `maxWidth` on the current layer's slot `name` when its content is wider than `room`.
    mutating func fit(_ name: SlotName, natural: Double, room: Double) {
        guard let index = layers.indices.last, layers[index].slots[name] != nil else { return }
        layers[index].slots[name]?.maxWidth = fittedWidth(natural: natural, room: room)
    }

    /// Writes the painted slots back on their layers.
    mutating func write(_ painted: StringMap<[SlotName: SlotStyle]>) {
        for index in layers.indices {
            if let slots = painted[layers[index].key] { layers[index].slots = slots }
        }
    }
}
