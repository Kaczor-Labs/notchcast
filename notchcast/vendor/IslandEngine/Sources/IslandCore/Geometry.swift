import Foundation

/// Where the shape is heading. x values are offsets from the screen's centre line, so the sensor
/// area always sits at 0; y values are from the top of the screen.
public struct ShapeTarget: Sendable, Codable, Equatable {
    public var left: Double
    public var right: Double
    public var top: Double
    public var height: Double
    public var radius: Double
    /// Detached capsule edges. When there is none they sit inside the pill's trailing end.
    public var bubbleLeft: Double
    public var bubbleRight: Double
    /// Detached capsule height. 0 when there is no second activity.
    public var bubbleHeight: Double

    public init(
        left: Double, right: Double, top: Double, height: Double, radius: Double,
        bubbleLeft: Double, bubbleRight: Double, bubbleHeight: Double
    ) {
        self.left = left
        self.right = right
        self.top = top
        self.height = height
        self.radius = radius
        self.bubbleLeft = bubbleLeft
        self.bubbleRight = bubbleRight
        self.bubbleHeight = bubbleHeight
    }
}

/// Leading and trailing widths of a pair of content slots.
public struct SlotPair: Sendable, Codable, Equatable {
    public var leading: Double
    public var trailing: Double

    public init(leading: Double, trailing: Double) {
        self.leading = leading
        self.trailing = trailing
    }
}

/// Natural content widths the shape has to fit, measured from the laid-out content.
public struct ContentMeasure: Sendable, Codable, Equatable {
    /// Compact content of the attached and the detached activity, for the two-pill split.
    public struct Split: Sendable, Codable, Equatable {
        public var attached: SlotPair
        public var detached: SlotPair

        public init(attached: SlotPair, detached: SlotPair) {
            self.attached = attached
            self.detached = detached
        }
    }

    public var leading: Double
    public var trailing: Double
    /// Minimal content shown in the attached pill (the fallback split).
    public var attached: Double
    /// Minimal content shown in the detached capsule (the fallback split).
    public var detached: Double
    public var split: Split?
    /// Height of the expanded regions laid out at the expanded width, without padding.
    public var expandedHeight: Double

    public init(
        leading: Double = 0, trailing: Double = 0, attached: Double = 0, detached: Double = 0,
        split: Split? = nil, expandedHeight: Double = 0
    ) {
        self.leading = leading
        self.trailing = trailing
        self.attached = attached
        self.detached = detached
        self.split = split
        self.expandedHeight = expandedHeight
    }

    /// No content at all.
    public static let empty = ContentMeasure()
}

/// The two pills of the compact split, as offsets from the screen's centre line.
public struct SplitLayout: Sendable, Equatable {
    public var left: Double
    public var right: Double
    public var bubbleLeft: Double
    public var bubbleRight: Double
}

/// The bubble's trailing slot at rest: its drawn width, its centre measured in from the bubble's
/// right edge, and the room the slot has.
public struct BubbleTrailing: Sendable, Equatable {
    public var width: Double
    public var fromRight: Double
    public var room: Double
}

private func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
    jsMin(upper, jsMax(lower, value))
}

/// The width the island lays out against: the container, but never wider than a phone.
public func islandScreenWidth(containerWidth: Double, metrics: IslandMetrics) -> Double {
    containerWidth > 0 ? jsMin(containerWidth, metrics.screen.width) : metrics.screen.width
}

/// Width the expanded regions are laid out at.
public func expandedWidth(screenWidth: Double, metrics: IslandMetrics) -> Double {
    screenWidth - 2 * metrics.expanded.sideInset
}

/// The two pills of the compact split, or nil when the content is too wide for them.
public func splitLayout(_ measure: ContentMeasure, metrics: IslandMetrics) -> SplitLayout? {
    guard let split = measure.split else { return nil }
    let s = metrics.split
    let sensor = metrics.compact.sensorWidth / 2
    func pair(_ slots: SlotPair, _ gap: Double) -> Double {
        slots.leading + slots.trailing + (slots.leading > 0 && slots.trailing > 0 ? gap : 0)
    }
    let attachedWidth = s.attached.outerPadding + pair(split.attached, s.attached.gap) + s.attached.innerPadding
    let detached = split.detached
    let bubbleWidth = s.detached.width > 0 && detached.trailing > 0
        ? s.detached.width
        : jsMax(
            metrics.minimal.detached.minWidth,
            s.detached.outerPadding + pair(detached, s.detached.gap)
                + (detached.trailing > 0 ? s.detached.trailingPadding : s.detached.outerPadding)
        )
    let left = -(sensor + attachedWidth)
    let bubbleLeft = sensor + metrics.minimal.gap
    let bubbleRight = bubbleLeft + bubbleWidth
    if bubbleRight - left > s.maxSpan { return nil }
    return SplitLayout(left: left, right: sensor, bubbleLeft: bubbleLeft, bubbleRight: bubbleRight)
}

/// The bubble's trailing slot for `detached` content in a bubble `bubbleWidth` wide, so the content
/// rides the bubble's right edge while the bubble springs out of the pill.
public func bubbleTrailing(_ detached: SlotPair, bubbleWidth: Double, metrics: IslandMetrics) -> BubbleTrailing {
    let d = metrics.split.detached
    if d.width <= 0 {
        return BubbleTrailing(
            width: detached.trailing, fromRight: d.trailingPadding + detached.trailing / 2, room: .infinity)
    }
    let start = d.outerPadding + detached.leading + d.slotGap
    let end = bubbleWidth - d.slotEnd
    let room = jsMax(0, end - start)
    return BubbleTrailing(width: jsMin(detached.trailing, room), fromRight: bubbleWidth - (start + end) / 2, room: room)
}

/// How far the compact pill reaches past the sensor on each side, `balance` applied.
public func compactSides(_ slots: SlotPair, metrics: IslandMetrics) -> SlotPair {
    let c = metrics.compact
    func side(_ slot: Double, _ inner: Double) -> Double {
        slot > 0 ? inner + jsMin(slot, c.maxSlotWidth) + c.edgePadding : 0
    }
    let leading = side(slots.leading, c.innerPadding.leading)
    let trailing = side(slots.trailing, c.innerPadding.trailing)
    // A side with nothing in it stays at the sensor: the rule is about two sides of content.
    if leading <= 0 || trailing <= 0 || c.balance <= 0 { return SlotPair(leading: leading, trailing: trailing) }
    return SlotPair(leading: jsMax(leading, trailing * c.balance), trailing: jsMax(trailing, leading * c.balance))
}

extension ShapeTarget {
    /// The resting shape of presentation `kind` for `measure`, on a screen `screenWidth` wide.
    public init(_ kind: PresentationKind, measure: ContentMeasure, screenWidth: Double, metrics: IslandMetrics) {
        let top = metrics.top
        switch kind {
        case .idle:
            let width = metrics.idle.width
            let height = metrics.idle.height
            self = .hidingBubble(
                left: -width / 2, right: width / 2, top: top, height: height, radius: height / 2, bubbleHeight: height)
        case .compact:
            let c = metrics.compact
            let sensor = c.sensorWidth / 2
            let sides = compactSides(SlotPair(leading: measure.leading, trailing: measure.trailing), metrics: metrics)
            let left = -jsMin(sensor + sides.leading, c.maxWidth / 2)
            let right = jsMin(sensor + sides.trailing, c.maxWidth / 2)
            self = .hidingBubble(
                left: left, right: right, top: top, height: c.height, radius: c.radius ?? c.height / 2,
                bubbleHeight: c.height)
        case .minimal:
            let m = metrics.minimal
            let sensor = metrics.compact.sensorWidth / 2
            if let split = splitLayout(measure, metrics: metrics) {
                self.init(
                    left: split.left, right: split.right, top: top, height: m.height, radius: m.height / 2,
                    bubbleLeft: split.bubbleLeft, bubbleRight: split.bubbleRight, bubbleHeight: m.height)
                return
            }
            // Fallback: the attached pill keeps the sensor's trailing end and grows left to fit.
            let left = measure.attached > 0
                ? -(sensor + m.attached.innerPadding + measure.attached + m.attached.outerPadding)
                : -sensor
            let right = sensor
            let bubbleWidth = jsMax(m.detached.minWidth, measure.detached + 2 * m.detached.padding)
            self.init(
                left: left, right: right, top: top, height: m.height, radius: m.height / 2,
                bubbleLeft: right + m.gap, bubbleRight: right + m.gap + bubbleWidth, bubbleHeight: m.height)
        case .expanded:
            let e = metrics.expanded
            let half = expandedWidth(screenWidth: screenWidth, metrics: metrics) / 2
            let height = clamp(measure.expandedHeight + e.padding.top + e.padding.bottom, e.minHeight, e.maxHeight)
            self = .hidingBubble(
                left: -half, right: half, top: e.top, height: height, radius: e.radius,
                bubbleHeight: metrics.compact.height)
        }
    }

    /// A shape with no bubble: its edges tucked inside the pill's trailing end, its height 0.
    private static func hidingBubble(
        left: Double, right: Double, top: Double, height: Double, radius: Double, bubbleHeight: Double
    ) -> ShapeTarget {
        ShapeTarget(
            left: left, right: right, top: top, height: height, radius: radius,
            bubbleLeft: right - bubbleHeight, bubbleRight: right, bubbleHeight: 0)
    }
}

extension ShapeTransition {
    /// The motion for a change between presentations. `swap` is true when the activity on show
    /// changes, `alert` when the expanded view being left was an alert.
    public init(from: PresentationKind, to: PresentationKind, swap: Bool, swelling: Bool, alert: Bool) {
        if from == to {
            self = .resize
        } else if to == .expanded {
            if from == .idle {
                self = .appearExpand
            } else if from == .minimal || swap {
                self = .swap
            } else {
                self = swelling ? .pressExpand : .expand
            }
        } else if from == .expanded {
            if to == .minimal {
                self = .collapseSplit
            } else if to == .idle {
                self = .dismiss
            } else {
                self = alert ? .alertCollapse : .collapse
            }
        } else if to == .idle {
            self = .dismiss
        } else if from == .idle {
            self = .appear
        } else if to == .minimal {
            self = .split
        } else {
            self = .unsplit
        }
    }
}
