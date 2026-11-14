import Foundation

extension IslandMetrics {
    static let standardScreen: Size = IslandMetrics.Size(width: 402, height: 874)

    static let standardIdle: Size = IslandMetrics.Size(width: 94.85, height: 36.84)

    static let standardCorner: Corner = IslandMetrics.Corner(smoothing: 0.72)

    static let standardCompact: Compact = IslandMetrics.Compact(
        height: 36.85,
        sensorWidth: 94.85,
        edgePadding: 7.18,
        innerPadding: IslandMetrics.Compact.InnerPadding(leading: -0.18, trailing: 0.07),
        maxSlotWidth: 72,
        maxWidth: 260,
        balance: 0.7475,
    )

    static let standardMinimal: Minimal = IslandMetrics.Minimal(
        height: 36.85,
        attached: IslandMetrics.Minimal.Attached(outerPadding: 7.09, innerPadding: 8.4),
        detached: IslandMetrics.Minimal.Detached(padding: 6.42, minWidth: 36.85),
        gap: 7.82,
    )

    static let standardSplit: Split = IslandMetrics.Split(
        attached: IslandMetrics.Split.Attached(outerPadding: 6.59, gap: 6.15, innerPadding: 8.18),
        detached: IslandMetrics.Split.Detached(
            outerPadding: 6.42,
            gap: 12,
            trailingPadding: 13.09,
            width: 62.18,
            slotGap: 6.085,
            slotEnd: 7.175,
        ),
        maxSpan: 290,
    )

    static let standardExpanded: Expanded = IslandMetrics.Expanded(
        sideInset: 13.83,
        top: 13.83,
        minHeight: 84,
        maxHeight: 180,
        radius: 47.9,
        cornerAspect: 1,
        cornerExponent: 2,
        padding: IslandMetrics.Expanded.Padding(top: 18.18, side: 18.5, bottom: 18.35, trailing: 17.81),
        bottomInset: 0,
        centerTop: 1.33,
        rowGap: 8,
        shadow: IslandMetrics.Expanded.Shadow(
            offsetY: 10.7,
            blur: 30.76,
            aspect: 1.018,
            opacity: 0.3533,
            tail: IslandMetrics.Expanded.Shadow.Tail(offsetY: 23.43, blur: 81.03, aspect: 1.084, strength: 0.0922),
            pull: IslandMetrics.Expanded.Shadow.Pull(side: 0.14, top: 0.083, bottom: 0.276, opacity: 0.3533),
            grain: IslandMetrics.Expanded.Shadow.Grain(levels: 0.6, full: 0.004),
        ),
    )

    static let standardContentClip: ContentClip = IslandMetrics.ContentClip(radius: 34.4, chamfer: 0)

    static let standardPress: Press = IslandMetrics.Press(squish: 0.09, swell: 0.187, bubbleSwell: 0.0622)

    static let standardBridge: Bridge = IslandMetrics.Bridge(handleSize: 2.4, spread: 0.3, maxGap: 5)

    static let standardContent: Content = IslandMetrics.Content(blur: 8, scale: 0.85, follow: 1, followMin: 0.2, followMax: 2.5)

    static let standardSensor: Sensor = IslandMetrics.Sensor(opacity: 1)

    static let standardKeyline: Keyline = IslandMetrics.Keyline(
        width: 1.5,
        alpha: 0.16,
        fullUntil: 0.04,
        noneFrom: 0.17,
        expandedDim: 0.07,
        ramp: 6,
    )

    public static let standard: IslandMetrics = IslandMetrics(
        screen: standardScreen,
        top: 13.91,
        idle: standardIdle,
        corner: standardCorner,
        compact: standardCompact,
        minimal: standardMinimal,
        split: standardSplit,
        expanded: standardExpanded,
        contentClip: standardContentClip,
        press: standardPress,
        bridge: standardBridge,
        content: standardContent,
        sensor: standardSensor,
        keyline: standardKeyline
    )
}
