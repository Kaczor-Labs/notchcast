import Foundation

extension IslandMotion {
    static let standardShapeAppear: SpringConfig = SpringConfig(response: 0.483, dampingFraction: 0.62)

    static let standardShapeExpand: SpringConfig = SpringConfig(response: 0.517, dampingFraction: 0.824)

    static let standardShapePressExpand: SpringConfig = SpringConfig(response: 0.387, dampingFraction: 0.792)

    static let standardShapeAppearExpand: SpringConfig = SpringConfig(response: 0.54, dampingFraction: 0.811)

    static let standardShapeSwap: SpringConfig = SpringConfig(response: 0.498, dampingFraction: 0.829)

    static let standardShapeCollapse: SpringConfig = SpringConfig(response: 0.479, dampingFraction: 0.894)

    static let standardShapeAlertCollapse: SpringConfig = SpringConfig(response: 0.535, dampingFraction: 0.84)

    static let standardShapeCollapseSplit: SpringConfig = SpringConfig(response: 0.4, dampingFraction: 0.9)

    static let standardShapeSplit: SpringConfig = SpringConfig(response: 0.505, dampingFraction: 0.815)

    static let standardShapeUnsplit: SpringConfig = SpringConfig(response: 0.487, dampingFraction: 0.794)

    static let standardShapeDismiss: SpringConfig = SpringConfig(response: 0.432, dampingFraction: 1.019)

    static let standardShapeResize: SpringConfig = SpringConfig(response: 0.5, dampingFraction: 0.82)

    static let standardShape: PerTransition<SpringConfig> = PerTransition([
        .appear: standardShapeAppear,
        .expand: standardShapeExpand,
        .pressExpand: standardShapePressExpand,
        .appearExpand: standardShapeAppearExpand,
        .swap: standardShapeSwap,
        .collapse: standardShapeCollapse,
        .alertCollapse: standardShapeAlertCollapse,
        .collapseSplit: standardShapeCollapseSplit,
        .split: standardShapeSplit,
        .unsplit: standardShapeUnsplit,
        .dismiss: standardShapeDismiss,
        .resize: standardShapeResize,
    ])

    static let standardAppearWide: AppearWide = IslandMotion.AppearWide(
        from: 150.18,
        to: 178.25,
        spring: SpringConfig(response: 0.47, dampingFraction: 0.74),
    )

    static let standardBodyAppear: DelayedSpring = DelayedSpring(response: 0.483, dampingFraction: 0.62, delay: 0)

    static let standardBodyExpand: DelayedSpring = DelayedSpring(response: 0.497, dampingFraction: 0.825, delay: 0)

    static let standardBodyPressExpand: DelayedSpring = DelayedSpring(response: 0.388, dampingFraction: 0.791, delay: 0)

    static let standardBodyAppearExpand: DelayedSpring = DelayedSpring(response: 0.523, dampingFraction: 0.817, delay: 0)

    static let standardBodySwap: DelayedSpring = DelayedSpring(response: 0.492, dampingFraction: 0.832, delay: 0.223)

    static let standardBodyCollapse: DelayedSpring = DelayedSpring(response: 0.453, dampingFraction: 0.928, delay: 0)

    static let standardBodyAlertCollapse: DelayedSpring = DelayedSpring(response: 0.481, dampingFraction: 0.908, delay: 0)

    static let standardBodyCollapseSplit: DelayedSpring = DelayedSpring(response: 0.481, dampingFraction: 0.884, delay: 0)

    static let standardBodySplit: DelayedSpring = DelayedSpring(response: 0.505, dampingFraction: 0.815, delay: 0)

    static let standardBodyUnsplit: DelayedSpring = DelayedSpring(response: 0.5, dampingFraction: 0.74, delay: 0)

    static let standardBodyDismiss: DelayedSpring = DelayedSpring(response: 0.442, dampingFraction: 0.97, delay: 0)

    static let standardBodyResize: DelayedSpring = DelayedSpring(response: 0.5, dampingFraction: 0.82, delay: 0)

    static let standardBody: PerTransition<DelayedSpring> = PerTransition([
        .appear: standardBodyAppear,
        .expand: standardBodyExpand,
        .pressExpand: standardBodyPressExpand,
        .appearExpand: standardBodyAppearExpand,
        .swap: standardBodySwap,
        .collapse: standardBodyCollapse,
        .alertCollapse: standardBodyAlertCollapse,
        .collapseSplit: standardBodyCollapseSplit,
        .split: standardBodySplit,
        .unsplit: standardBodyUnsplit,
        .dismiss: standardBodyDismiss,
        .resize: standardBodyResize,
    ])

    static let standardCornerAppear: DelayedSpring = DelayedSpring(response: 0.483, dampingFraction: 0.62, delay: 0)

    static let standardCornerExpand: DelayedSpring = DelayedSpring(response: 0.448, dampingFraction: 0.87, delay: 0.018)

    static let standardCornerPressExpand: DelayedSpring = DelayedSpring(response: 0.32, dampingFraction: 0.831, delay: 0.019)

    static let standardCornerAppearExpand: DelayedSpring = DelayedSpring(response: 0.452, dampingFraction: 0.865, delay: 0.02)

    static let standardCornerSwap: DelayedSpring = DelayedSpring(response: 0.41, dampingFraction: 0.888, delay: 0.244)

    static let standardCornerCollapse: DelayedSpring = DelayedSpring(response: 0.449, dampingFraction: 0.94, delay: 0.01)

    static let standardCornerAlertCollapse: DelayedSpring = DelayedSpring(response: 0.47, dampingFraction: 0.86, delay: 0.009)

    static let standardCornerCollapseSplit: DelayedSpring = DelayedSpring(response: 0.36, dampingFraction: 0.865, delay: 0)

    static let standardCornerSplit: DelayedSpring = DelayedSpring(response: 0.505, dampingFraction: 0.815, delay: 0)

    static let standardCornerUnsplit: DelayedSpring = DelayedSpring(response: 0.5, dampingFraction: 0.74, delay: 0)

    static let standardCornerDismiss: DelayedSpring = DelayedSpring(response: 0.442, dampingFraction: 0.97, delay: 0)

    static let standardCornerResize: DelayedSpring = DelayedSpring(response: 0.5, dampingFraction: 0.82, delay: 0)

    static let standardCorner: PerTransition<DelayedSpring> = PerTransition([
        .appear: standardCornerAppear,
        .expand: standardCornerExpand,
        .pressExpand: standardCornerPressExpand,
        .appearExpand: standardCornerAppearExpand,
        .swap: standardCornerSwap,
        .collapse: standardCornerCollapse,
        .alertCollapse: standardCornerAlertCollapse,
        .collapseSplit: standardCornerCollapseSplit,
        .split: standardCornerSplit,
        .unsplit: standardCornerUnsplit,
        .dismiss: standardCornerDismiss,
        .resize: standardCornerResize,
    ])

    static let standardCornerLeadCollapseSplit: CornerLead = CornerLead(
        response: 0.481,
        dampingFraction: 0.884,
        delay: 0,
        trailing: CornerLead.Trailing(above: 60, below: 50),
    )

    static let standardCornerLead: PartialPerTransition<CornerLead> = PartialPerTransition([
        .collapseSplit: standardCornerLeadCollapseSplit,
    ])

    static let standardViaIdle: PerTransition<Double> = PerTransition([
        .appear: 0,
        .expand: 0,
        .pressExpand: 0,
        .appearExpand: 0,
        .swap: 0.223,
        .collapse: 0.311,
        .alertCollapse: 0.29,
        .collapseSplit: 0,
        .split: 0.215,
        .unsplit: 0.203,
        .dismiss: 0,
        .resize: 0,
    ])

    static let standardRetarget: Retarget = IslandMotion.Retarget(
        collapse: SpringConfig(response: 0.447, dampingFraction: 1),
        alertCollapse: SpringConfig(response: 0.527, dampingFraction: 0.837),
    )

    static let standardTailAppear: ShapeTail = ShapeTail(
        width: TailLegs(
            lean: TailLean(by: 0, at: 0, max: 0, response: 0.5, dampingFraction: 1),
            settle: TailSettle(at: 0.28, response: 0.332, dampingFraction: 1),
        ),
        height: TailLegs(
            lean: TailLean(by: 0, at: 0, max: 0, response: 0.5, dampingFraction: 1),
            settle: TailSettle(at: 0, response: 0.5, dampingFraction: 1),
        ),
        top: TailLegs(
            lean: TailLean(by: 0, at: 0, max: 0, response: 0.5, dampingFraction: 1),
            settle: TailSettle(at: 0, response: 0.5, dampingFraction: 1),
        ),
    )

    static let standardTailExpand: ShapeTail = ShapeTail(
        width: TailLegs(
            lean: TailLean(by: 0, at: 0, max: 0, response: 0.5, dampingFraction: 1),
            settle: TailSettle(at: 0, response: 0.5, dampingFraction: 1),
        ),
        height: TailLegs(
            lean: TailLean(by: 0, at: 0, max: 0, response: 0.5, dampingFraction: 1),
            settle: TailSettle(at: 0, response: 0.5, dampingFraction: 1),
        ),
        top: TailLegs(
            lean: TailLean(by: 0, at: 0, max: 0, response: 0.5, dampingFraction: 1),
            settle: TailSettle(at: 0, response: 0.5, dampingFraction: 1),
        ),
    )

    static let standardTailPressExpand: ShapeTail = ShapeTail(
        width: TailLegs(
            lean: TailLean(by: 0, at: 0, max: 0, response: 0.5, dampingFraction: 1),
            settle: TailSettle(at: 0, response: 0.5, dampingFraction: 1),
        ),
        height: TailLegs(
            lean: TailLean(by: 0, at: 0, max: 0, response: 0.5, dampingFraction: 1),
            settle: TailSettle(at: 0, response: 0.5, dampingFraction: 1),
        ),
        top: TailLegs(
            lean: TailLean(by: 0, at: 0, max: 0, response: 0.5, dampingFraction: 1),
            settle: TailSettle(at: 0, response: 0.5, dampingFraction: 1),
        ),
    )

    static let standardTailAppearExpand: ShapeTail = ShapeTail(
        width: TailLegs(
            lean: TailLean(by: 0, at: 0, max: 0, response: 0.5, dampingFraction: 1),
            settle: TailSettle(at: 0, response: 0.5, dampingFraction: 1),
        ),
        height: TailLegs(
            lean: TailLean(by: 0, at: 0, max: 0, response: 0.5, dampingFraction: 1),
            settle: TailSettle(at: 0, response: 0.5, dampingFraction: 1),
        ),
        top: TailLegs(
            lean: TailLean(by: 0, at: 0, max: 0, response: 0.5, dampingFraction: 1),
            settle: TailSettle(at: 0, response: 0.5, dampingFraction: 1),
        ),
    )

    static let standardTailSwap: ShapeTail = ShapeTail(
        width: TailLegs(
            lean: TailLean(by: 0, at: 0, max: 0, response: 0.5, dampingFraction: 1),
            settle: TailSettle(at: 0, response: 0.5, dampingFraction: 1),
        ),
        height: TailLegs(
            lean: TailLean(by: 0, at: 0, max: 0, response: 0.5, dampingFraction: 1),
            settle: TailSettle(at: 0, response: 0.5, dampingFraction: 1),
        ),
        top: TailLegs(
            lean: TailLean(by: 0, at: 0, max: 0, response: 0.5, dampingFraction: 1),
            settle: TailSettle(at: 0, response: 0.5, dampingFraction: 1),
        ),
    )

    static let standardTailCollapse: ShapeTail = ShapeTail(
        width: TailLegs(
            lean: TailLean(by: 0.025, at: 0.396, max: 8, response: 0.3, dampingFraction: 0.866),
            settle: TailSettle(at: 0.608, response: 0.409, dampingFraction: 1),
        ),
        height: TailLegs(
            lean: TailLean(by: 0.019, at: 0.242, max: 4, response: 0.287, dampingFraction: 0.724),
            settle: TailSettle(at: 0.56, response: 0.372, dampingFraction: 1),
        ),
        top: TailLegs(
            lean: TailLean(by: 0, at: 0, max: 0, response: 0.5, dampingFraction: 1),
            settle: TailSettle(at: 0.454, response: 0.28, dampingFraction: 1),
        ),
    )

    static let standardTailAlertCollapse: ShapeTail = ShapeTail(
        width: TailLegs(
            lean: TailLean(by: 0.017, at: 0.366, max: 8, response: 0.357, dampingFraction: 0.704),
            settle: TailSettle(at: 0.652, response: 0.351, dampingFraction: 1),
        ),
        height: TailLegs(
            lean: TailLean(by: 0.02, at: 0.248, max: 4, response: 0.318, dampingFraction: 0.718),
            settle: TailSettle(at: 0.548, response: 0.396, dampingFraction: 1),
        ),
        top: TailLegs(
            lean: TailLean(by: 0, at: 0, max: 0, response: 0.5, dampingFraction: 1),
            settle: TailSettle(at: 0.569, response: 0.15, dampingFraction: 1),
        ),
    )

    static let standardTailCollapseSplit: ShapeTail = ShapeTail(
        width: TailLegs(
            lean: TailLean(by: 0, at: 0, max: 0, response: 0.5, dampingFraction: 1),
            settle: TailSettle(at: 0, response: 0.5, dampingFraction: 1),
        ),
        height: TailLegs(
            lean: TailLean(by: 0.026, at: 0.308, max: 4, response: 0.477, dampingFraction: 0.838),
            settle: TailSettle(at: 0.55, response: 0.383, dampingFraction: 1),
        ),
        top: TailLegs(
            lean: TailLean(by: 0, at: 0, max: 0, response: 0.5, dampingFraction: 1),
            settle: TailSettle(at: 0.489, response: 0.349, dampingFraction: 1),
        ),
    )

    static let standardTailSplit: ShapeTail = ShapeTail(
        width: TailLegs(
            lean: TailLean(by: 0, at: 0, max: 0, response: 0.5, dampingFraction: 1),
            settle: TailSettle(at: 0, response: 0.5, dampingFraction: 1),
        ),
        height: TailLegs(
            lean: TailLean(by: 0, at: 0, max: 0, response: 0.5, dampingFraction: 1),
            settle: TailSettle(at: 0, response: 0.5, dampingFraction: 1),
        ),
        top: TailLegs(
            lean: TailLean(by: 0, at: 0, max: 0, response: 0.5, dampingFraction: 1),
            settle: TailSettle(at: 0, response: 0.5, dampingFraction: 1),
        ),
    )

    static let standardTailUnsplit: ShapeTail = ShapeTail(
        width: TailLegs(
            lean: TailLean(by: 0, at: 0, max: 0, response: 0.5, dampingFraction: 1),
            settle: TailSettle(at: 0.646, response: 0.445, dampingFraction: 1),
        ),
        height: TailLegs(
            lean: TailLean(by: 0, at: 0, max: 0, response: 0.5, dampingFraction: 1),
            settle: TailSettle(at: 0, response: 0.5, dampingFraction: 1),
        ),
        top: TailLegs(
            lean: TailLean(by: 0, at: 0, max: 0, response: 0.5, dampingFraction: 1),
            settle: TailSettle(at: 0, response: 0.5, dampingFraction: 1),
        ),
    )

    static let standardTailDismiss: ShapeTail = ShapeTail(
        width: TailLegs(
            lean: TailLean(by: 0.042, at: 0.15, max: 4, response: 0.46, dampingFraction: 0.728),
            settle: TailSettle(at: 0.548, response: 0.4, dampingFraction: 1),
        ),
        height: TailLegs(
            lean: TailLean(by: 0, at: 0, max: 0, response: 0.5, dampingFraction: 1),
            settle: TailSettle(at: 0, response: 0.5, dampingFraction: 1),
        ),
        top: TailLegs(
            lean: TailLean(by: 0, at: 0, max: 0, response: 0.5, dampingFraction: 1),
            settle: TailSettle(at: 0, response: 0.5, dampingFraction: 1),
        ),
    )

    static let standardTailResize: ShapeTail = ShapeTail(
        width: TailLegs(
            lean: TailLean(by: 0, at: 0, max: 0, response: 0.5, dampingFraction: 1),
            settle: TailSettle(at: 0, response: 0.5, dampingFraction: 1),
        ),
        height: TailLegs(
            lean: TailLean(by: 0, at: 0, max: 0, response: 0.5, dampingFraction: 1),
            settle: TailSettle(at: 0, response: 0.5, dampingFraction: 1),
        ),
        top: TailLegs(
            lean: TailLean(by: 0, at: 0, max: 0, response: 0.5, dampingFraction: 1),
            settle: TailSettle(at: 0, response: 0.5, dampingFraction: 1),
        ),
    )

    static let standardTail: PerTransition<ShapeTail> = PerTransition([
        .appear: standardTailAppear,
        .expand: standardTailExpand,
        .pressExpand: standardTailPressExpand,
        .appearExpand: standardTailAppearExpand,
        .swap: standardTailSwap,
        .collapse: standardTailCollapse,
        .alertCollapse: standardTailAlertCollapse,
        .collapseSplit: standardTailCollapseSplit,
        .split: standardTailSplit,
        .unsplit: standardTailUnsplit,
        .dismiss: standardTailDismiss,
        .resize: standardTailResize,
    ])

    static let standardBubble: Bubble = IslandMotion.Bubble(
        split: DelayedSpring(response: 0.376, dampingFraction: 0.811, delay: 0.345),
        collapseSplit: DelayedSpring(response: 0.3, dampingFraction: 0.8, delay: 0.24),
        unsplit: SpringConfig(response: 0.25, dampingFraction: 1),
        unsplitSlide: SpringConfig(response: 0.42, dampingFraction: 1),
        unsplitAbsorb: 0.205,
        absorbExpand: 0.222,
        absorbExpandCorner: DelayedSpring(response: 0.49, dampingFraction: 0.826, delay: 0.001),
        joinLead: 0.012,
        collapseSplitVia: IslandMotion.Bubble.CollapseSplitVia(
            dip: 24,
            at: 0.16,
            response: 0.22,
            dampingFraction: 1,
            down: SpringConfig(response: 0.41, dampingFraction: 0.55),
        ),
        collapseSplitRise: DelayedSpring(response: 0.12, dampingFraction: 1, delay: 0.1),
        collapseSplitLift: IslandMotion.Bubble.CollapseSplitLift(
            by: 1.139,
            response: 0.475,
            dampingFraction: 0.581,
            back: IslandMotion.Bubble.CollapseSplitLift.Back(at: 0.318, response: 0.485, dampingFraction: 0.878),
        ),
        collapseSplitSpread: IslandMotion.Bubble.CollapseSplitSpread(
            left: 4.903,
            right: 5.467,
            at: 0.566,
            response: 0.457,
            dampingFraction: 0.816,
            rightPeel: IslandMotion.Bubble.CollapseSplitSpread.RightPeel(
                at: 0.144,
                to: 3.431,
                response: 0.354,
                dampingFraction: 0.826,
            ),
            rightSettle: IslandMotion.Bubble.CollapseSplitSpread.RightLeg(at: 0.41, response: 0.149, dampingFraction: 0.912),
            rightBack: IslandMotion.Bubble.CollapseSplitSpread.RightLeg(at: 0.464, response: 0.5, dampingFraction: 1),
            neckGap: 3.28,
            neckPower: 0.2,
            neckTip: NeckTip(length: 1.4, reach: 2.4, until: 0.49),
            bubbleFrom: 12,
            kick: 3,
        ),
    )

    static let standardLag: PerTransition<Double> = PerTransition([
        .appear: 0,
        .expand: 0,
        .pressExpand: 0,
        .appearExpand: 0,
        .swap: 0,
        .collapse: 0,
        .alertCollapse: 0,
        .collapseSplit: 0.035,
        .split: 0,
        .unsplit: 0,
        .dismiss: 0,
        .resize: 0,
    ])

    static let standardContent: Content = IslandMotion.Content(
        enter: DelayedSpring(response: 0.3, dampingFraction: 1, delay: 0.12),
        exit: DelayedSpring(response: 0.12, dampingFraction: 1, delay: 0),
        carryResponseMin: 0.1,
    )

    static let standardPress: Press = IslandMotion.Press(
        down: SpringConfig(response: 0.45, dampingFraction: 1),
        up: SpringConfig(response: 0.36, dampingFraction: 0.62),
        swell: SpringConfig(response: 0.803, dampingFraction: 0.641),
        swellTime: 0.22,
        decide: 0.1,
        release: SpringConfig(response: 0.3, dampingFraction: 1.5),
        idleRelease: IslandMotion.Press.IdleRelease(
            spring: SpringConfig(response: 0.53, dampingFraction: 0.77),
            carry: 0.03,
        ),
        idleWiden: IdleWiden(
            by: 1.12,
            rise: SpringConfig(response: 0.425, dampingFraction: 0.925),
            hold: 0.57,
            fall: SpringConfig(response: 0.3, dampingFraction: 1.15),
        ),
        tapReturn: 0.22,
        releaseReturn: 0.17,
        idleTapReturn: 0.2,
        holdReturn: 0.236,
        bubbleSwell: SpringConfig(response: 0.509, dampingFraction: 0.05),
    )

    static let standardGroup: Group = IslandMotion.Group(handoff: 1.445, window: 6.014)

    static let standardKeyline: Keyline = IslandMotion.Keyline(dip: 0.15, dipAt: 0.5, backAt: 1.1)

    static let standardShadowRamp: SpringConfig = SpringConfig(response: 0.36, dampingFraction: 1)

    static let standardShadowRampPress: SpringConfig = SpringConfig(response: 0.507, dampingFraction: 0.839)

    static let standardBlurSkirt: BlurSkirt = BlurSkirt(
        width: 13.3,
        gain: 0.036,
        max: 0.045,
        floor: 0.004,
        exitGain: 0.036,
        power: 0.5,
        dim: 0,
        tail: 0,
    )

    static let standardReduced: Reduced = IslandMotion.Reduced(duration: 0.2)


    public static let standard: IslandMotion = IslandMotion(
        shape: standardShape,
        appearWide: standardAppearWide,
        body: standardBody,
        corner: standardCorner,
        cornerLead: standardCornerLead,
        viaIdle: standardViaIdle,
        collapseLift: 1.4,
        retarget: standardRetarget,
        tail: standardTail,
        bubble: standardBubble,
        lag: standardLag,
        content: standardContent,
        contentTiming: standardContentTiming,
        press: standardPress,
        longPress: 0.216,
        longPressBubble: 0.224,
        alertContentDelay: 0.12,
        group: standardGroup,
        keyline: standardKeyline,
        shadowRamp: standardShadowRamp,
        shadowRampPress: standardShadowRampPress,
        alertHold: 5.975,
        alertHoldIdle: 5.969,
        blurSkirt: standardBlurSkirt,
        reduced: standardReduced
    )
}
