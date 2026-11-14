import Foundation

/// How one expanded region comes in apart from its layer (`ContentMotion.regions`).
public struct RegionLag: Sendable, Codable, Equatable {
    /// Seconds its opacity lags the layer's presence.
    public var fade: Double
    /// Seconds its blur and scale lag the layer's presence.
    public var blur: Double
    /// Defaults to 0. Its blur is multiplied by 1 + this × (1 - presence). Below 0 it starts
    /// sharper.
    public var soften: Double?
    /// Defaults to 0. The opacity it may show ahead of its lag, on the layer's own presence.
    public var lead: Double?
    /// Defaults to the layer's `enterBlur`. This region's own peak incoming blur in points.
    public var peak: Double?
    /// Defaults to the layer's `scale`. The scale this region grows from as it comes in.
    public var scale: Double?
    /// Defaults to 0. Points the region sits above its place while it comes in.
    public var lift: Double?
    /// Defaults to the layer's `fade`. Its opacity is its lagged presence to this power.
    public var power: Double?

    public init(
        fade: Double,
        blur: Double,
        soften: Double? = nil,
        lead: Double? = nil,
        peak: Double? = nil,
        scale: Double? = nil,
        lift: Double? = nil,
        power: Double? = nil
    ) {
        self.fade = fade
        self.blur = blur
        self.soften = soften
        self.lead = lead
        self.peak = peak
        self.scale = scale
        self.lift = lift
        self.power = power
    }
}

/// How content crosses over during one transition.
public struct ContentMotion: Sendable, Codable, Equatable {
    public struct Absorb: Sendable, Codable, Equatable {
        public var enter: DelayedSpring
        public var centerDelay: Double
        public var regions: PerRegion<RegionLag>?
        public var clipFollow: Double?
        public var regionBottomAnchor: PerRegion<Double>?
        /// The absorbing change's own peak incoming blur.
        public var enterBlur: Double?
        /// Defaults to this transition's. How the layer the absorbing change takes out fades.
        public var exitFade: Double?
        /// Defaults to this transition's. How its accent's blur rises.
        public var exitSharpen: Double?

        public init(
            enter: DelayedSpring,
            centerDelay: Double,
            regions: PerRegion<RegionLag>? = nil,
            clipFollow: Double? = nil,
            regionBottomAnchor: PerRegion<Double>? = nil,
            enterBlur: Double? = nil,
            exitFade: Double? = nil,
            exitSharpen: Double? = nil
        ) {
            self.enter = enter
            self.centerDelay = centerDelay
            self.regions = regions
            self.clipFollow = clipFollow
            self.regionBottomAnchor = regionBottomAnchor
            self.enterBlur = enterBlur
            self.exitFade = exitFade
            self.exitSharpen = exitSharpen
        }
    }

    public struct AfterHandoff: Sendable, Codable, Equatable {
        public var enter: DelayedSpring
        public var fade: Double
        public var regions: PerRegion<RegionLag>?

        public init(enter: DelayedSpring, fade: Double, regions: PerRegion<RegionLag>? = nil) {
            self.enter = enter
            self.fade = fade
            self.regions = regions
        }
    }

    public struct Wide: Sendable, Codable, Equatable {
        /// Applies when the shape the layer comes into is at least this wide.
        public var from: Double
        public var scale: Double?
        public var enterBlur: Double?
        public var sharpen: Double?
        public var trailingEnterBlur: Double?
        public var trailingEnter: DelayedSpring?
        public var trailingScale: Double?
        public var trailingEnterClear: Double?
        public var enterGlow: Double?
        public var leadingFade: Double?

        public init(
            from: Double,
            scale: Double? = nil,
            enterBlur: Double? = nil,
            sharpen: Double? = nil,
            trailingEnterBlur: Double? = nil,
            trailingEnter: DelayedSpring? = nil,
            trailingScale: Double? = nil,
            trailingEnterClear: Double? = nil,
            enterGlow: Double? = nil,
            leadingFade: Double? = nil
        ) {
            self.from = from
            self.scale = scale
            self.enterBlur = enterBlur
            self.sharpen = sharpen
            self.trailingEnterBlur = trailingEnterBlur
            self.trailingEnter = trailingEnter
            self.trailingScale = trailingScale
            self.trailingEnterClear = trailingEnterClear
            self.enterGlow = enterGlow
            self.leadingFade = leadingFade
        }
    }

    public struct ExitWide: Sendable, Codable, Equatable {
        /// Applies when the compact pill the layer leaves is at least this wide.
        public var from: Double
        public var scale: Double?
        public var blur: Double?
        public var exitScale: Double?
        public var exitTravel: Double?
        public var exitLeadingFade: Double?
        public var exitBlur: Double?
        public var exitSharpen: Double?
        public var exitFade: Double?
        public var anchor: Double?
        public var trailingExitPower: Double?

        public init(
            from: Double,
            scale: Double? = nil,
            blur: Double? = nil,
            exitScale: Double? = nil,
            exitTravel: Double? = nil,
            exitLeadingFade: Double? = nil,
            exitBlur: Double? = nil,
            exitSharpen: Double? = nil,
            exitFade: Double? = nil,
            anchor: Double? = nil,
            trailingExitPower: Double? = nil
        ) {
            self.from = from
            self.scale = scale
            self.blur = blur
            self.exitScale = exitScale
            self.exitTravel = exitTravel
            self.exitLeadingFade = exitLeadingFade
            self.exitBlur = exitBlur
            self.exitSharpen = exitSharpen
            self.exitFade = exitFade
            self.anchor = anchor
            self.trailingExitPower = trailingExitPower
        }
    }

    public struct AfterAlert: Sendable, Codable, Equatable {
        public var enter: DelayedSpring?
        public var bubbleEnter: DelayedSpring?
        public var bubbleDelay: Double?
        public var bubbleFade: Double?
        public var bubbleResolve: Double?
        public var bubbleTrailingFade: Double?
        public var bubbleTrailingSlide: ByPower?
        public var bubbleBlur: Double?
        public var bubbleSharpen: Double?
        public var bubbleScale: Double?
        public var bubbleSpread: Double?
        public var bubbleHold: Double?
        public var bubbleSettle: BubbleSettle?

        public init(
            enter: DelayedSpring? = nil,
            bubbleEnter: DelayedSpring? = nil,
            bubbleDelay: Double? = nil,
            bubbleFade: Double? = nil,
            bubbleResolve: Double? = nil,
            bubbleTrailingFade: Double? = nil,
            bubbleTrailingSlide: ByPower? = nil,
            bubbleBlur: Double? = nil,
            bubbleSharpen: Double? = nil,
            bubbleScale: Double? = nil,
            bubbleSpread: Double? = nil,
            bubbleHold: Double? = nil,
            bubbleSettle: BubbleSettle? = nil
        ) {
            self.enter = enter
            self.bubbleEnter = bubbleEnter
            self.bubbleDelay = bubbleDelay
            self.bubbleFade = bubbleFade
            self.bubbleResolve = bubbleResolve
            self.bubbleTrailingFade = bubbleTrailingFade
            self.bubbleTrailingSlide = bubbleTrailingSlide
            self.bubbleBlur = bubbleBlur
            self.bubbleSharpen = bubbleSharpen
            self.bubbleScale = bubbleScale
            self.bubbleSpread = bubbleSpread
            self.bubbleHold = bubbleHold
            self.bubbleSettle = bubbleSettle
        }
    }

    /// A distance or blur `by` that closes as (1 - presence) ^ `power`.
    public struct ByPower: Sendable, Codable, Equatable {
        public var by: Double
        public var power: Double

        public init(by: Double, power: Double) {
            self.by = by
            self.power = power
        }
    }

    public struct Ride: Sendable, Codable, Equatable {
        public var by: Double
        public var max: Double

        public init(by: Double, max: Double) {
            self.by = by
            self.max = max
        }
    }

    public struct PartStep: Sendable, Codable, Equatable {
        public var at: Double
        public var by: Double
        public var spring: SpringConfig

        public init(at: Double, by: Double, spring: SpringConfig) {
            self.at = at
            self.by = by
            self.spring = spring
        }
    }

    public var enter: DelayedSpring
    public var exit: DelayedSpring
    /// How the detached bubble's content leaves when it joins the pill. Defaults to `exit`. A
    /// `response` of 0 cuts it at once; a negative `delay` leads a known join.
    public var bubbleExit: DelayedSpring?
    /// Defaults to false. With `bubbleExit`, only the bubble's accent is cut; its text leaves with
    /// the layer.
    public var bubbleExitAccent: Bool?
    /// The incoming detached bubble's presence on its own spring from the change's start. Without
    /// it the bubble rides the layer, `bubbleDelay` behind.
    public var bubbleEnter: DelayedSpring?
    /// The incoming compact trailing slot on its own presence spring from the change's start,
    /// replacing `trailingDelay`.
    public var trailingEnter: DelayedSpring?
    /// Defaults to `enterBlur`. The incoming trailing slot's peak blur with `trailingEnter`.
    public var trailingEnterBlur: Double?
    /// Defaults to `scale`. The scale an incoming compact trailing slot grows from, for its size
    /// and place.
    public var trailingScale: Double?
    /// Defaults to 0. Coming into a compact pill, each slot's opacity is at least this times the
    /// layer's presence.
    public var enterGlow: Double?
    /// Defaults to `enter` and `centerDelay`. How the incoming layer comes in when the change
    /// absorbs the bubble as a lobe.
    public var absorb: Absorb?
    /// Defaults to `enter`, `fade` and `regions`. How the incoming layer comes in when the change
    /// ends a group's handoff.
    public var afterHandoff: AfterHandoff?
    /// How the incoming layer comes in when its shape is at least `from` points wide, over this
    /// transition's own fields.
    public var wide: Wide?
    /// How the leaving layer leaves when the compact pill it leaves is at least `from` points wide.
    public var exitWide: ExitWide?
    /// How the incoming layer comes in when the change leaves an alert whose hold ran out.
    public var afterAlert: AfterAlert?
    /// The incoming bubble's accent settles into its size from below.
    public var bubbleSettle: BubbleSettle?
    /// Peak blur in points of the outgoing layer.
    public var blur: Double
    /// Peak blur in points of the incoming layer.
    public var enterBlur: Double
    /// Scale content arrives from and leaves to.
    public var scale: Double
    /// Opacity of the incoming layer is presence to this power.
    public var fade: Double
    /// The same for the outgoing layer.
    public var exitFade: Double
    /// Extra seconds the detached bubble's content waits before it comes in; negative brings it in
    /// first.
    public var bubbleDelay: Double
    /// Extra seconds the compact trailing slot waits before it comes in.
    public var trailingDelay: Double
    /// The trailing slot's presence is raised to this power while a layer goes. 1 leaves them
    /// together.
    public var trailingExitPower: Double
    /// Where compact and split content sits while the shape morphs. 0 keeps each slot's fraction of
    /// the width; 1 scales about the centre; below 0 pushes toward the ends.
    public var anchor: Double
    /// The incoming blur is (1 - presence) to this power times `enterBlur`.
    public var sharpen: Double
    /// The leading slot comes in at presence to `fade` × this.
    public var leadingFade: Double
    /// Defaults to 1. How much of the blur's wide part (`blurSkirt`) this transition draws.
    public var skirt: Double?
    /// Scale the detached bubble's content comes in from.
    public var bubbleScale: Double
    /// How far the bubble's content spreads out while it comes in. 0 rides the moving bubble.
    public var bubbleSpread: Double
    /// Defaults to 0. How far the bubble's content is stretched across while it comes in.
    public var bubbleStretch: Double?
    /// Defaults to 1. The power the accent's stretch closes on.
    public var bubbleStretchPower: Double?
    /// Where the bubble's incoming content scales from, as a fraction of the row's height from its
    /// top.
    public var bubbleOrigin: Double?
    /// Defaults to 0. With `bubbleOrigin`, the presence up to which the content keeps its larger
    /// form.
    public var bubbleHold: Double?
    /// Defaults to `bubbleSharpen`. With `bubbleHold`, the power the returning form resolves on.
    public var bubbleResolve: Double?
    /// Defaults to `fade`. The incoming bubble content's opacity is presence to this power.
    public var bubbleFade: Double?
    /// Defaults to `scale`. The scale a leaving accent shrinks toward.
    public var exitScale: Double?
    /// Defaults to `scale`. The scale a leaving compact accent's place follows with `anchor`.
    public var exitTravel: Double?
    /// Defaults to 1. A leaving accent fades at presence to `exitFade` × this.
    public var exitLeadingFade: Double?
    /// Defaults to `scale`. The scale an incoming accent grows from.
    public var enterScale: Double?
    /// Defaults to 0. While the compact pill is narrower than at rest, an incoming accent is drawn
    /// narrower.
    public var enterSqueeze: Double?
    /// Defaults to 0. Which edge of the squeezed accent holds its place: 0 inner, 1 outer.
    public var enterSqueezeOrigin: Double?
    /// Defaults to 0. An incoming accent is also drawn narrower by presence ^ this.
    public var enterNarrow: Double?
    /// Defaults to 0. Points the incoming trailing slot starts toward the sensor; negative starts
    /// it away.
    public var trailingSlide: Double?
    /// Defaults to 1. The power `trailingSlide` closes on.
    public var trailingSlidePower: Double?
    /// Defaults to 0. The share of presence still to come when the incoming blur reaches zero.
    public var enterClear: Double?
    /// Defaults to `enterClear`. The same for the incoming trailing slot alone.
    public var trailingEnterClear: Double?
    /// Defaults to 0. How far an incoming expanded layer's content clip follows the content.
    public var clipFollow: Double?
    /// Defaults to `blur`. The leaving accent's peak blur.
    public var exitBlur: Double?
    /// Defaults to `blur`. The leaving detached bubble's accent's peak blur.
    public var bubbleExitBlur: Double?
    /// Defaults to 1. A leaving accent blurs by `exitBlur` × (1 - presence) ^ this points.
    public var exitSharpen: Double?
    /// Defaults to 0. Coming back into a split, how far the attached pill's slots keep toward the
    /// row's middle.
    public var rowAnchor: Double?
    /// Defaults to none. The returning bubble's leading content is cut by a capsule whose end comes
    /// in as 1 - (1 - presence) ^ this.
    public var bubbleCap: Double?
    /// Defaults to `bubbleFade`. The incoming bubble's trailing slot comes in at presence to this
    /// power.
    public var bubbleTrailingFade: Double?
    /// Points the incoming bubble's text starts right of its place, closing as (1 - presence) ^
    /// `power`.
    public var bubbleTrailingSlide: ByPower?
    /// The incoming bubble text's own blur, `by` × (1 - presence) ^ `power` points.
    public var bubbleTrailingBlur: ByPower?
    /// The bubble's incoming blur is `bubbleBlur` × (1 - presence) ^ `bubbleSharpen`, capped at
    /// `enterBlur`.
    public var bubbleBlur: Double
    /// The power the bubble's incoming blur follows.
    public var bubbleSharpen: Double
    /// Defaults to `enterBlur`. The most the bubble's incoming content is blurred.
    public var bubbleBlurMax: Double?
    /// Defaults to 0. Seconds ahead the bubble's content rides, at the bubble's current speed.
    public var bubbleLead: Double?
    /// Defaults to 0. Points the bubble's left edge must come out of the pill before the lead is
    /// whole.
    public var bubbleLeadRamp: Double?
    /// Defaults to 2. The power `bubbleLeadRamp`'s share grows in on.
    public var bubbleLeadPower: Double?
    /// Defaults to 0. Points the leaving bubble's accent slides toward the sensor.
    public var bubbleExitSlide: Double?
    /// Defaults to 1. The power `bubbleExitSlide` closes on.
    public var bubbleExitSlidePower: Double?
    /// Extra seconds the expanded view's center region waits before it comes in.
    public var centerDelay: Double
    /// Defaults to 0. How far the expanded regions follow the island's bottom edge while its height
    /// is off rest.
    public var bottomAnchor: Double?
    /// How far (`by`) the trailing slot keeps its resting distance from the pill's end, at most
    /// `max` points.
    public var trailingRide: Ride?
    /// Coming into a split, `at` seconds in the attached pill's slots step `by` points and settle
    /// on `spring`.
    public var partStep: PartStep?
    /// Defaults to `anchor` when that is 0 or more, else 0. The leaving trailing slot's own
    /// `anchor`.
    public var trailingExitAnchor: Double?
    /// Defaults to `metrics.content.follow`. How far compact and split content scales with its
    /// container.
    public var follow: Double?
    /// Per region of the incoming expanded view, how it lags the layer's presence.
    public var regions: PerRegion<RegionLag>?
    /// Per region of the outgoing expanded view, its own fade power in place of `exitFade`.
    public var regionExitFade: PerRegion<Double>?
    /// Defaults to `bottomAnchor` for every region. Per region, its own `bottomAnchor`.
    public var regionBottomAnchor: PerRegion<Double>?

    public init(
        enter: DelayedSpring,
        exit: DelayedSpring,
        bubbleExit: DelayedSpring? = nil,
        bubbleExitAccent: Bool? = nil,
        bubbleEnter: DelayedSpring? = nil,
        trailingEnter: DelayedSpring? = nil,
        trailingEnterBlur: Double? = nil,
        trailingScale: Double? = nil,
        enterGlow: Double? = nil,
        absorb: Absorb? = nil,
        afterHandoff: AfterHandoff? = nil,
        wide: Wide? = nil,
        exitWide: ExitWide? = nil,
        afterAlert: AfterAlert? = nil,
        bubbleSettle: BubbleSettle? = nil,
        blur: Double,
        enterBlur: Double,
        scale: Double,
        fade: Double,
        exitFade: Double,
        bubbleDelay: Double,
        trailingDelay: Double,
        trailingExitPower: Double,
        anchor: Double,
        sharpen: Double,
        leadingFade: Double,
        skirt: Double? = nil,
        bubbleScale: Double,
        bubbleSpread: Double,
        bubbleStretch: Double? = nil,
        bubbleStretchPower: Double? = nil,
        bubbleOrigin: Double? = nil,
        bubbleHold: Double? = nil,
        bubbleResolve: Double? = nil,
        bubbleFade: Double? = nil,
        exitScale: Double? = nil,
        exitTravel: Double? = nil,
        exitLeadingFade: Double? = nil,
        enterScale: Double? = nil,
        enterSqueeze: Double? = nil,
        enterSqueezeOrigin: Double? = nil,
        enterNarrow: Double? = nil,
        trailingSlide: Double? = nil,
        trailingSlidePower: Double? = nil,
        enterClear: Double? = nil,
        trailingEnterClear: Double? = nil,
        clipFollow: Double? = nil,
        exitBlur: Double? = nil,
        bubbleExitBlur: Double? = nil,
        exitSharpen: Double? = nil,
        rowAnchor: Double? = nil,
        bubbleCap: Double? = nil,
        bubbleTrailingFade: Double? = nil,
        bubbleTrailingSlide: ByPower? = nil,
        bubbleTrailingBlur: ByPower? = nil,
        bubbleBlur: Double,
        bubbleSharpen: Double,
        bubbleBlurMax: Double? = nil,
        bubbleLead: Double? = nil,
        bubbleLeadRamp: Double? = nil,
        bubbleLeadPower: Double? = nil,
        bubbleExitSlide: Double? = nil,
        bubbleExitSlidePower: Double? = nil,
        centerDelay: Double,
        bottomAnchor: Double? = nil,
        trailingRide: Ride? = nil,
        partStep: PartStep? = nil,
        trailingExitAnchor: Double? = nil,
        follow: Double? = nil,
        regions: PerRegion<RegionLag>? = nil,
        regionExitFade: PerRegion<Double>? = nil,
        regionBottomAnchor: PerRegion<Double>? = nil
    ) {
        self.enter = enter
        self.exit = exit
        self.bubbleExit = bubbleExit
        self.bubbleExitAccent = bubbleExitAccent
        self.bubbleEnter = bubbleEnter
        self.trailingEnter = trailingEnter
        self.trailingEnterBlur = trailingEnterBlur
        self.trailingScale = trailingScale
        self.enterGlow = enterGlow
        self.absorb = absorb
        self.afterHandoff = afterHandoff
        self.wide = wide
        self.exitWide = exitWide
        self.afterAlert = afterAlert
        self.bubbleSettle = bubbleSettle
        self.blur = blur
        self.enterBlur = enterBlur
        self.scale = scale
        self.fade = fade
        self.exitFade = exitFade
        self.bubbleDelay = bubbleDelay
        self.trailingDelay = trailingDelay
        self.trailingExitPower = trailingExitPower
        self.anchor = anchor
        self.sharpen = sharpen
        self.leadingFade = leadingFade
        self.skirt = skirt
        self.bubbleScale = bubbleScale
        self.bubbleSpread = bubbleSpread
        self.bubbleStretch = bubbleStretch
        self.bubbleStretchPower = bubbleStretchPower
        self.bubbleOrigin = bubbleOrigin
        self.bubbleHold = bubbleHold
        self.bubbleResolve = bubbleResolve
        self.bubbleFade = bubbleFade
        self.exitScale = exitScale
        self.exitTravel = exitTravel
        self.exitLeadingFade = exitLeadingFade
        self.enterScale = enterScale
        self.enterSqueeze = enterSqueeze
        self.enterSqueezeOrigin = enterSqueezeOrigin
        self.enterNarrow = enterNarrow
        self.trailingSlide = trailingSlide
        self.trailingSlidePower = trailingSlidePower
        self.enterClear = enterClear
        self.trailingEnterClear = trailingEnterClear
        self.clipFollow = clipFollow
        self.exitBlur = exitBlur
        self.bubbleExitBlur = bubbleExitBlur
        self.exitSharpen = exitSharpen
        self.rowAnchor = rowAnchor
        self.bubbleCap = bubbleCap
        self.bubbleTrailingFade = bubbleTrailingFade
        self.bubbleTrailingSlide = bubbleTrailingSlide
        self.bubbleTrailingBlur = bubbleTrailingBlur
        self.bubbleBlur = bubbleBlur
        self.bubbleSharpen = bubbleSharpen
        self.bubbleBlurMax = bubbleBlurMax
        self.bubbleLead = bubbleLead
        self.bubbleLeadRamp = bubbleLeadRamp
        self.bubbleLeadPower = bubbleLeadPower
        self.bubbleExitSlide = bubbleExitSlide
        self.bubbleExitSlidePower = bubbleExitSlidePower
        self.centerDelay = centerDelay
        self.bottomAnchor = bottomAnchor
        self.trailingRide = trailingRide
        self.partStep = partStep
        self.trailingExitAnchor = trailingExitAnchor
        self.follow = follow
        self.regions = regions
        self.regionExitFade = regionExitFade
        self.regionBottomAnchor = regionBottomAnchor
    }
}
