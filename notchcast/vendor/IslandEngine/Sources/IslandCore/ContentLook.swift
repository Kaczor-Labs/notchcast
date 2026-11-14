import Foundation

/// How a layer blurs, scales and fades while it is out, set by the transition that moved it.
public struct LayerLook: Sendable, Equatable {
    public var blur: Double
    public var enterBlur: Double
    public var scale: Double
    public var fade: Double
    public var exitFade: Double
    public var bubbleDelay: Double
    public var trailingDelay: Double
    public var trailingExitPower: Double
    public var anchor: Double
    public var sharpen: Double
    public var leadingFade: Double
    public var bubbleScale: Double
    public var bubbleSpread: Double
    public var bubbleBlur: Double
    public var bubbleSharpen: Double
    public var centerDelay: Double
    public var bubbleStretch: Double
    public var bubbleStretchPower: Double
    /// A factor on the blur's wide part.
    public var skirt: Double
    public var bubbleBlurMax: Double?
    /// The bubble's lead in seconds of its left edge's speed (0: none).
    public var bubbleLead: Double
    /// Points the lead grows in over (0: at once), and the power it grows with.
    public var bubbleLeadRamp: Double
    public var bubbleLeadPower: Double
    /// Points a leaving bubble's accent slides left (0: none), and its power.
    public var bubbleExitSlide: Double
    public var bubbleExitSlidePower: Double
    public var bubbleOrigin: Double?
    public var bubbleHold: Double
    public var bubbleResolve: Double?
    public var bubbleFade: Double?
    public var exitScale: Double?
    public var exitTravel: Double?
    public var exitLeadingFade: Double
    public var enterScale: Double?
    public var enterSqueeze: Double
    public var enterSqueezeOrigin: Double
    public var enterNarrow: Double
    public var trailingSlide: Double
    public var trailingSlidePower: Double
    public var enterClear: Double
    public var trailingEnterClear: Double
    public var clipFollow: Double
    public var exitBlur: Double?
    public var bubbleExitBlur: Double?
    public var exitSharpen: Double
    public var rowAnchor: Double
    public var bubbleCap: Double
    public var bubbleTrailingFade: Double
    public var bubbleTrailingSlide: ContentMotion.ByPower?
    public var bubbleTrailingBlur: ContentMotion.ByPower?
    /// The share the incoming bubble's accent starts smaller (0: none).
    public var bubbleSettle: Double
    public var trailingEnterBlur: Double?
    /// The incoming compact trailing slot's own start scale, or nil for `scale`.
    public var trailingScale: Double?
    public var enterGlow: Double
    public var bottomAnchor: Double
    public var trailingRide: ContentMotion.Ride?
    public var trailingExitAnchor: Double?
    public var follow: Double?
    public var partStep: ContentMotion.PartStep?
    public var bubbleExitAccent: Bool
    public var regions: PerRegion<RegionLag>
    public var regionExitFade: PerRegion<Double>
    public var regionBottomAnchor: PerRegion<Double>

    /// The look of a transition's timing, unset fields at their defaults.
    public init(_ timing: ContentMotion) {
        blur = timing.blur
        enterBlur = timing.enterBlur
        scale = timing.scale
        fade = timing.fade
        exitFade = timing.exitFade
        bubbleDelay = timing.bubbleDelay
        trailingDelay = timing.trailingDelay
        trailingExitPower = timing.trailingExitPower
        anchor = timing.anchor
        sharpen = timing.sharpen
        leadingFade = timing.leadingFade
        bubbleScale = timing.bubbleScale
        bubbleSpread = timing.bubbleSpread
        bubbleBlur = timing.bubbleBlur
        bubbleSharpen = timing.bubbleSharpen
        centerDelay = timing.centerDelay
        bubbleStretch = timing.bubbleStretch ?? 0
        bubbleStretchPower = timing.bubbleStretchPower ?? 1
        skirt = timing.skirt ?? 1
        bubbleBlurMax = timing.bubbleBlurMax
        bubbleLead = timing.bubbleLead ?? 0
        bubbleLeadRamp = timing.bubbleLeadRamp ?? 0
        bubbleLeadPower = timing.bubbleLeadPower ?? 2
        bubbleExitSlide = timing.bubbleExitSlide ?? 0
        bubbleExitSlidePower = timing.bubbleExitSlidePower ?? 1
        bubbleOrigin = timing.bubbleOrigin
        bubbleHold = timing.bubbleHold ?? 0
        bubbleResolve = timing.bubbleResolve
        bubbleFade = timing.bubbleFade
        exitScale = timing.exitScale
        exitTravel = timing.exitTravel
        exitLeadingFade = timing.exitLeadingFade ?? 1
        enterScale = timing.enterScale
        enterSqueeze = timing.enterSqueeze ?? 0
        enterSqueezeOrigin = timing.enterSqueezeOrigin ?? 0
        enterNarrow = timing.enterNarrow ?? 0
        trailingSlide = timing.trailingSlide ?? 0
        trailingSlidePower = timing.trailingSlidePower ?? 1
        enterClear = timing.enterClear ?? 0
        trailingEnterClear = timing.trailingEnterClear ?? timing.enterClear ?? 0
        clipFollow = timing.clipFollow ?? 0
        exitBlur = timing.exitBlur
        bubbleExitBlur = timing.bubbleExitBlur
        exitSharpen = timing.exitSharpen ?? 1
        rowAnchor = timing.rowAnchor ?? 0
        bubbleCap = timing.bubbleCap ?? 0
        bubbleTrailingFade = timing.bubbleTrailingFade ?? 0
        bubbleTrailingSlide = timing.bubbleTrailingSlide
        bubbleTrailingBlur = timing.bubbleTrailingBlur
        bubbleSettle = timing.bubbleSettle?.depth ?? 0
        trailingEnterBlur = timing.trailingEnterBlur
        trailingScale = timing.trailingScale
        enterGlow = timing.enterGlow ?? 0
        bottomAnchor = timing.bottomAnchor ?? 0
        trailingRide = timing.trailingRide
        trailingExitAnchor = timing.trailingExitAnchor
        follow = timing.follow
        partStep = timing.partStep
        bubbleExitAccent = timing.bubbleExitAccent ?? false
        regions = timing.regions ?? PerRegion()
        regionExitFade = timing.regionExitFade ?? PerRegion()
        regionBottomAnchor = timing.regionBottomAnchor ?? PerRegion()
    }

    /// The look of a layer no transition has moved yet.
    public static func standard(metrics m: IslandMetrics) -> LayerLook {
        let blur = m.content.blur
        let scale = m.content.scale
        let still = DelayedSpring(response: 0, dampingFraction: 1, delay: 0)
        return LayerLook(ContentMotion(
            enter: still, exit: still, blur: blur, enterBlur: blur, scale: scale, fade: 1, exitFade: 1,
            bubbleDelay: 0, trailingDelay: 0, trailingExitPower: 1, anchor: 0, sharpen: 1, leadingFade: 1,
            bubbleScale: scale, bubbleSpread: 0, bubbleBlur: blur, bubbleSharpen: 1, centerDelay: 0))
    }

    /// The longest delay (s) by which this look's slots or regions read its presence coming in.
    var lag: Double {
        var longest = max(0, bubbleDelay, trailingDelay, centerDelay)
        for region in ExpandedRegion.allCases {
            if let lag = regions[region] { longest = max(longest, lag.fade, lag.blur) }
        }
        return longest
    }

    /// This look with a wide compact pill's exit look laid over it.
    func leavingWide(_ wide: ContentMotion.ExitWide) -> LayerLook {
        var look = self
        if let value = wide.scale { look.scale = value }
        if let value = wide.blur { look.blur = value }
        if let value = wide.exitScale { look.exitScale = value }
        if let value = wide.exitTravel { look.exitTravel = value }
        if let value = wide.exitLeadingFade { look.exitLeadingFade = value }
        if let value = wide.exitBlur { look.exitBlur = value }
        if let value = wide.exitSharpen { look.exitSharpen = value }
        if let value = wide.exitFade { look.exitFade = value }
        if let value = wide.anchor { look.anchor = value }
        if let value = wide.trailingExitPower { look.trailingExitPower = value }
        return look
    }
}

/// What a change's content follows: the transition's timing, varied by what the change is.
func contentTiming(
    _ base: ContentMotion, absorbing: Bool, alerting: Bool, handingOff: Bool, width: Double
) -> ContentMotion {
    var timing = base
    if absorbing, let absorb = base.absorb {
        timing.enter = absorb.enter
        timing.centerDelay = absorb.centerDelay
        if let value = absorb.regions { timing.regions = value }
        if let value = absorb.clipFollow { timing.clipFollow = value }
        if let value = absorb.regionBottomAnchor { timing.regionBottomAnchor = value }
        if let value = absorb.enterBlur { timing.enterBlur = value }
        if let value = absorb.exitFade { timing.exitFade = value }
        if let value = absorb.exitSharpen { timing.exitSharpen = value }
    } else if alerting, let after = base.afterAlert {
        // The bubble keeps the layer's presence unless the alert's look brings an entry of its own.
        timing.bubbleEnter = nil
        if let value = after.enter { timing.enter = value }
        if let value = after.bubbleEnter { timing.bubbleEnter = value }
        if let value = after.bubbleDelay { timing.bubbleDelay = value }
        if let value = after.bubbleFade { timing.bubbleFade = value }
        if let value = after.bubbleResolve { timing.bubbleResolve = value }
        if let value = after.bubbleTrailingFade { timing.bubbleTrailingFade = value }
        if let value = after.bubbleTrailingSlide { timing.bubbleTrailingSlide = value }
        if let value = after.bubbleBlur { timing.bubbleBlur = value }
        if let value = after.bubbleSharpen { timing.bubbleSharpen = value }
        if let value = after.bubbleScale { timing.bubbleScale = value }
        if let value = after.bubbleSpread { timing.bubbleSpread = value }
        if let value = after.bubbleHold { timing.bubbleHold = value }
        if let value = after.bubbleSettle { timing.bubbleSettle = value }
    } else if handingOff, let after = base.afterHandoff {
        timing.enter = after.enter
        timing.fade = after.fade
        if let value = after.regions { timing.regions = value }
    }
    guard let wide = base.wide, width >= wide.from else { return timing }
    if let value = wide.scale { timing.scale = value }
    if let value = wide.enterBlur { timing.enterBlur = value }
    if let value = wide.sharpen { timing.sharpen = value }
    if let value = wide.trailingEnterBlur { timing.trailingEnterBlur = value }
    if let value = wide.trailingEnter { timing.trailingEnter = value }
    if let value = wide.trailingScale { timing.trailingScale = value }
    if let value = wide.trailingEnterClear { timing.trailingEnterClear = value }
    if let value = wide.enterGlow { timing.enterGlow = value }
    if let value = wide.leadingFade { timing.leadingFade = value }
    return timing
}
