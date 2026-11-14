import Foundation

/// Every size the island draws, in points (1 CSS px is 1 point). Calibration edits this one table.
public struct IslandMetrics: Sendable, Codable, Equatable {
    public struct Size: Sendable, Codable, Equatable {
        public var width: Double
        public var height: Double

        public init(width: Double, height: Double) {
            self.width = width
            self.height = height
        }
    }

    /// Screen the defaults are tuned for. Wider containers clamp to this width.
    public var screen: Size
    /// Gap from the top of the screen (or container) to the top of the pill.
    public var top: Double
    /// Resting pill with no activity: the hardware cutout, centred on the screen.
    public var idle: Size
    public var corner: Corner
    public var compact: Compact
    public var minimal: Minimal
    public var split: Split
    public var expanded: Expanded
    public var contentClip: ContentClip
    public var press: Press
    public var bridge: Bridge
    public var content: Content
    /// The camera and sensor housing, drawn over the content. 1 draws it, 0 turns it off.
    public var sensor: Sensor
    /// A thin grey band just outside the black edge that separates the island from a dark page.
    public var keyline: Keyline

    public init(
        screen: Size,
        top: Double,
        idle: Size,
        corner: Corner,
        compact: Compact,
        minimal: Minimal,
        split: Split,
        expanded: Expanded,
        contentClip: ContentClip,
        press: Press,
        bridge: Bridge,
        content: Content,
        sensor: Sensor,
        keyline: Keyline
    ) {
        self.screen = screen
        self.top = top
        self.idle = idle
        self.corner = corner
        self.compact = compact
        self.minimal = minimal
        self.split = split
        self.expanded = expanded
        self.contentClip = contentClip
        self.press = press
        self.bridge = bridge
        self.content = content
        self.sensor = sensor
        self.keyline = keyline
    }

    /// Every outline has continuous corners: a circular arc eased into the straight edges.
    public struct Corner: Sendable, Codable, Equatable {
        public var smoothing: Double

        public init(smoothing: Double) {
            self.smoothing = smoothing
        }
    }

    public struct Compact: Sendable, Codable, Equatable {
        public struct InnerPadding: Sendable, Codable, Equatable {
            public var leading: Double
            public var trailing: Double

            public init(leading: Double, trailing: Double) {
                self.leading = leading
                self.trailing = trailing
            }
        }

        public var height: Double
        /// Width kept clear in the middle for the camera and sensors (the idle pill).
        public var sensorWidth: Double
        /// Space between the pill edge and the leading or trailing content.
        public var edgePadding: Double
        /// Space between the sensor and the content on each side. Negative tucks under it.
        public var innerPadding: InnerPadding
        /// Widest a leading or trailing slot may grow.
        public var maxSlotWidth: Double
        /// Each side fits its own content, so the pill sits off centre when they differ.
        public var maxWidth: Double
        /// Least share of the longer side's extent the shorter reaches. 0 fits each alone.
        public var balance: Double

        public init(
            height: Double,
            sensorWidth: Double,
            edgePadding: Double,
            innerPadding: InnerPadding,
            maxSlotWidth: Double,
            maxWidth: Double,
            balance: Double
        ) {
            self.height = height
            self.sensorWidth = sensorWidth
            self.edgePadding = edgePadding
            self.innerPadding = innerPadding
            self.maxSlotWidth = maxSlotWidth
            self.maxWidth = maxWidth
            self.balance = balance
        }
    }

    public struct Minimal: Sendable, Codable, Equatable {
        public struct Attached: Sendable, Codable, Equatable {
            public var outerPadding: Double
            public var innerPadding: Double

            public init(outerPadding: Double, innerPadding: Double) {
                self.outerPadding = outerPadding
                self.innerPadding = innerPadding
            }
        }

        public struct Detached: Sendable, Codable, Equatable {
            public var padding: Double
            public var minWidth: Double

            public init(padding: Double, minWidth: Double) {
                self.padding = padding
                self.minWidth = minWidth
            }
        }

        public var height: Double
        /// Attached pill: the content sits left of the sensor with this padding on each side of it.
        public var attached: Attached
        /// Detached capsule: padding either side of its content, never narrower than a circle.
        public var detached: Detached
        /// Gap between the attached pill's trailing end and the detached capsule.
        public var gap: Double

        public init(height: Double, attached: Attached, detached: Detached, gap: Double) {
            self.height = height
            self.attached = attached
            self.detached = detached
            self.gap = gap
        }
    }

    /// Both pills show their activity's compact leading and trailing content.
    public struct Split: Sendable, Codable, Equatable {
        public struct Attached: Sendable, Codable, Equatable {
            public var outerPadding: Double
            public var gap: Double
            public var innerPadding: Double

            public init(outerPadding: Double, gap: Double, innerPadding: Double) {
                self.outerPadding = outerPadding
                self.gap = gap
                self.innerPadding = innerPadding
            }
        }

        public struct Detached: Sendable, Codable, Equatable {
            public var outerPadding: Double
            public var gap: Double
            public var trailingPadding: Double
            public var width: Double
            public var slotGap: Double
            public var slotEnd: Double

            public init(
                outerPadding: Double,
                gap: Double,
                trailingPadding: Double,
                width: Double,
                slotGap: Double,
                slotEnd: Double
            ) {
                self.outerPadding = outerPadding
                self.gap = gap
                self.trailingPadding = trailingPadding
                self.width = width
                self.slotGap = slotGap
                self.slotEnd = slotEnd
            }
        }

        /// Attached pill: padding before leading, between leading and trailing, before the sensor.
        public var attached: Attached
        /// Bubble. A `width` of 0 sizes it to its content, `gap` apart, plus `trailingPadding`.
        public var detached: Detached
        /// Widest the attached pill plus bubble may span. Wider content falls back to `minimal`.
        public var maxSpan: Double

        public init(attached: Attached, detached: Detached, maxSpan: Double) {
            self.attached = attached
            self.detached = detached
            self.maxSpan = maxSpan
        }
    }

    public struct Expanded: Sendable, Codable, Equatable {
        public struct Padding: Sendable, Codable, Equatable {
            public var top: Double
            public var side: Double
            public var bottom: Double
            public var trailing: Double?

            public init(top: Double, side: Double, bottom: Double, trailing: Double? = nil) {
                self.top = top
                self.side = side
                self.bottom = bottom
                self.trailing = trailing
            }
        }

        /// Soft shadow under the expanded island: a key layer and a broad, faint `tail`.
        public struct Shadow: Sendable, Codable, Equatable {
            public struct Tail: Sendable, Codable, Equatable {
                public var offsetY: Double
                public var blur: Double
                public var aspect: Double
                public var strength: Double

                public init(offsetY: Double, blur: Double, aspect: Double, strength: Double) {
                    self.offsetY = offsetY
                    self.blur = blur
                    self.aspect = aspect
                    self.strength = strength
                }
            }

            /// The outline is drawn inset by how far the shadow darkens the stage outside the edge.
            public struct Pull: Sendable, Codable, Equatable {
                public var side: Double
                public var top: Double
                public var bottom: Double
                public var opacity: Double

                public init(side: Double, top: Double, bottom: Double, opacity: Double) {
                    self.side = side
                    self.top = top
                    self.bottom = bottom
                    self.opacity = opacity
                }
            }

            /// Fixed per-device-pixel noise dithering the shadow's alpha. `levels` 0 turns it off.
            public struct Grain: Sendable, Codable, Equatable {
                public var levels: Double
                public var full: Double

                public init(levels: Double, full: Double) {
                    self.levels = levels
                    self.full = full
                }
            }

            public var offsetY: Double
            /// Twice the vertical standard deviation, as in CSS drop-shadow.
            public var blur: Double
            /// Scales the blur sideways.
            public var aspect: Double
            /// 0 turns the whole shadow off.
            public var opacity: Double
            public var tail: Tail
            public var pull: Pull
            public var grain: Grain

            public init(
                offsetY: Double,
                blur: Double,
                aspect: Double,
                opacity: Double,
                tail: Tail,
                pull: Pull,
                grain: Grain
            ) {
                self.offsetY = offsetY
                self.blur = blur
                self.aspect = aspect
                self.opacity = opacity
                self.tail = tail
                self.pull = pull
                self.grain = grain
            }
        }

        /// Inset from each side of the screen.
        public var sideInset: Double
        public var top: Double
        public var minHeight: Double
        public var maxHeight: Double
        /// Corner radius: the arc of the continuous corner.
        public var radius: Double
        /// With `corner.smoothing` 0, 1 and 2 draw circular corners.
        public var cornerAspect: Double
        public var cornerExponent: Double
        /// Padding between the pill edge and the regions. `trailing` falls back to `side`.
        public var padding: Padding
        /// Extra side inset of the bottom region.
        public var bottomInset: Double
        /// Extra space between the sensor's bottom edge and the center region.
        public var centerTop: Double
        /// Gap between the top row (leading, center, trailing) and the bottom region.
        public var rowGap: Double
        public var shadow: Shadow

        public init(
            sideInset: Double,
            top: Double,
            minHeight: Double,
            maxHeight: Double,
            radius: Double,
            cornerAspect: Double,
            cornerExponent: Double,
            padding: Padding,
            bottomInset: Double,
            centerTop: Double,
            rowGap: Double,
            shadow: Shadow
        ) {
            self.sideInset = sideInset
            self.top = top
            self.minHeight = minHeight
            self.maxHeight = maxHeight
            self.radius = radius
            self.cornerAspect = cornerAspect
            self.cornerExponent = cornerExponent
            self.padding = padding
            self.bottomInset = bottomInset
            self.centerTop = centerTop
            self.rowGap = rowGap
            self.shadow = shadow
        }
    }

    public struct ContentClip: Sendable, Codable, Equatable {
        /// Content is clipped to a rounded rectangle concentric with the island, up to this radius.
        public var radius: Double
        /// Above 0 cuts the corners at 45 degrees with legs of chamfer × radius instead.
        public var chamfer: Double

        public init(radius: Double, chamfer: Double) {
            self.radius = radius
            self.chamfer = chamfer
        }
    }

    public struct Press: Sendable, Codable, Equatable {
        /// How much the pill grows while held in a controlled pressed state.
        public var squish: Double
        /// Long-press swell target about the centre.
        public var swell: Double
        /// The detached bubble's swell. Defaults to `swell`.
        public var bubbleSwell: Double?

        public init(squish: Double, swell: Double, bubbleSwell: Double? = nil) {
            self.squish = squish
            self.swell = swell
            self.bubbleSwell = bubbleSwell
        }
    }

    public struct Bridge: Sendable, Codable, Equatable {
        /// Metaball handle length. Larger values make a fatter, gooier neck.
        public var handleSize: Double
        /// Metaball spread of the neck.
        public var spread: Double
        /// The neck thins to nothing as the gap to the detached capsule reaches this many points.
        public var maxGap: Double

        public init(handleSize: Double, spread: Double, maxGap: Double) {
            self.handleSize = handleSize
            self.spread = spread
            self.maxGap = maxGap
        }
    }

    public struct Content: Sendable, Codable, Equatable {
        /// Default peak blur in points while content crossfades.
        public var blur: Double
        /// Default scale content arrives from and leaves to.
        public var scale: Double
        /// How far content follows the container's size while the shape morphs. 0 keeps its size.
        public var follow: Double
        /// Lower bound of the follow scale.
        public var followMin: Double
        /// Upper bound of the follow scale.
        public var followMax: Double

        public init(blur: Double, scale: Double, follow: Double, followMin: Double, followMax: Double) {
            self.blur = blur
            self.scale = scale
            self.follow = follow
            self.followMin = followMin
            self.followMax = followMax
        }
    }

    public struct Sensor: Sendable, Codable, Equatable {
        public var opacity: Double

        public init(opacity: Double) {
            self.opacity = opacity
        }
    }

    public struct Keyline: Sendable, Codable, Equatable {
        public var width: Double
        /// Strength over a black page.
        public var alpha: Double
        /// Page luma (0 to 1, gamma-encoded Rec. 709) up to which the band stays at full strength.
        public var fullUntil: Double
        /// Page luma from which there is no band.
        public var noneFrom: Double
        /// How much weaker the band is on the fully expanded island.
        public var expandedDim: Double
        /// It grows in over this many points of width beyond idle, so idle shows none.
        public var ramp: Double

        public init(width: Double, alpha: Double, fullUntil: Double, noneFrom: Double, expandedDim: Double, ramp: Double) {
            self.width = width
            self.alpha = alpha
            self.fullUntil = fullUntil
            self.noneFrom = noneFrom
            self.expandedDim = expandedDim
            self.ramp = ramp
        }
    }
}

/// One measured point of the keyline's fade: a page luma and the band's strength there.
public struct KeylineFadePoint: Sendable, Codable, Equatable {
    /// Page luma, 0 to 1, gamma-encoded Rec. 709.
    public var luma: Double
    /// Strength as a share of `keyline.alpha`.
    public var share: Double

    public init(luma: Double, share: Double) {
        self.luma = luma
        self.share = share
    }
}

/// Measured points between the keyline's full plateau and `noneFrom`, interpolated in log space.
public let keylineFade: [KeylineFadePoint] = [
    KeylineFadePoint(luma: 0.0706, share: 0.328),
    KeylineFadePoint(luma: 0.1104, share: 0.109),
]
