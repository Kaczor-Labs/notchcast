import Foundation

extension IslandMotion {
    public struct Bubble: Sendable, Codable, Equatable {
        public struct CollapseSplitVia: Sendable, Codable, Equatable {
            public var dip: Double
            public var at: Double
            public var response: Double
            public var dampingFraction: Double
            public var blendDuration: Double?
            public var down: SpringConfig

            public init(
                dip: Double,
                at: Double,
                response: Double,
                dampingFraction: Double,
                blendDuration: Double? = nil,
                down: SpringConfig
            ) {
                self.dip = dip
                self.at = at
                self.response = response
                self.dampingFraction = dampingFraction
                self.blendDuration = blendDuration
                self.down = down
            }

            public var spring: SpringConfig {
                SpringConfig(response: response, dampingFraction: dampingFraction, blendDuration: blendDuration)
            }
        }

        public struct CollapseSplitLift: Sendable, Codable, Equatable {
            public struct Back: Sendable, Codable, Equatable {
                public var at: Double
                public var response: Double
                public var dampingFraction: Double
                public var blendDuration: Double?

                public init(at: Double, response: Double, dampingFraction: Double, blendDuration: Double? = nil) {
                    self.at = at
                    self.response = response
                    self.dampingFraction = dampingFraction
                    self.blendDuration = blendDuration
                }

                public var spring: SpringConfig {
                    SpringConfig(response: response, dampingFraction: dampingFraction, blendDuration: blendDuration)
                }
            }

            public var by: Double
            public var response: Double
            public var dampingFraction: Double
            public var blendDuration: Double?
            public var back: Back

            public init(
                by: Double,
                response: Double,
                dampingFraction: Double,
                blendDuration: Double? = nil,
                back: Back
            ) {
                self.by = by
                self.response = response
                self.dampingFraction = dampingFraction
                self.blendDuration = blendDuration
                self.back = back
            }

            public var spring: SpringConfig {
                SpringConfig(response: response, dampingFraction: dampingFraction, blendDuration: blendDuration)
            }
        }

        public struct CollapseSplitSpread: Sendable, Codable, Equatable {
            public struct RightPeel: Sendable, Codable, Equatable {
                public var at: Double
                public var to: Double
                public var response: Double
                public var dampingFraction: Double
                public var blendDuration: Double?

                public init(
                    at: Double,
                    to: Double,
                    response: Double,
                    dampingFraction: Double,
                    blendDuration: Double? = nil
                ) {
                    self.at = at
                    self.to = to
                    self.response = response
                    self.dampingFraction = dampingFraction
                    self.blendDuration = blendDuration
                }

                public var spring: SpringConfig {
                    SpringConfig(response: response, dampingFraction: dampingFraction, blendDuration: blendDuration)
                }
            }

            public struct RightLeg: Sendable, Codable, Equatable {
                public var at: Double
                public var response: Double
                public var dampingFraction: Double
                public var blendDuration: Double?

                public init(at: Double, response: Double, dampingFraction: Double, blendDuration: Double? = nil) {
                    self.at = at
                    self.response = response
                    self.dampingFraction = dampingFraction
                    self.blendDuration = blendDuration
                }

                public var spring: SpringConfig {
                    SpringConfig(response: response, dampingFraction: dampingFraction, blendDuration: blendDuration)
                }
            }

            public var left: Double
            public var right: Double
            public var at: Double
            public var response: Double
            public var dampingFraction: Double
            public var blendDuration: Double?
            public var rightPeel: RightPeel
            public var rightSettle: RightLeg
            public var rightBack: RightLeg
            public var neckGap: Double
            public var neckPower: Double
            /// Unset draws none. After the neck's first break each end keeps a short pointed nub.
            public var neckTip: NeckTip?
            public var bubbleFrom: Double
            public var kick: Double?

            public init(
                left: Double,
                right: Double,
                at: Double,
                response: Double,
                dampingFraction: Double,
                blendDuration: Double? = nil,
                rightPeel: RightPeel,
                rightSettle: RightLeg,
                rightBack: RightLeg,
                neckGap: Double,
                neckPower: Double,
                neckTip: NeckTip? = nil,
                bubbleFrom: Double,
                kick: Double? = nil
            ) {
                self.left = left
                self.right = right
                self.at = at
                self.response = response
                self.dampingFraction = dampingFraction
                self.blendDuration = blendDuration
                self.rightPeel = rightPeel
                self.rightSettle = rightSettle
                self.rightBack = rightBack
                self.neckGap = neckGap
                self.neckPower = neckPower
                self.neckTip = neckTip
                self.bubbleFrom = bubbleFrom
                self.kick = kick
            }

            public var spring: SpringConfig {
                SpringConfig(response: response, dampingFraction: dampingFraction, blendDuration: blendDuration)
            }
        }

        public var split: DelayedSpring
        public var collapseSplit: DelayedSpring
        public var unsplit: SpringConfig
        public var unsplitSlide: SpringConfig
        public var unsplitAbsorb: Double
        /// Defaults to `viaIdle.unsplit`. When a swap absorbing the bubble turns toward expanded.
        public var absorbExpand: Double?
        /// Defaults to `corner.swap`. The corner's spring when a swap absorbs the bubble.
        public var absorbExpandCorner: DelayedSpring?
        /// Defaults to 0. Seconds a decided long-press on the bubble starts the join's shape early.
        public var joinLead: Double?
        public var collapseSplitVia: CollapseSplitVia
        public var collapseSplitRise: DelayedSpring
        public var collapseSplitLift: CollapseSplitLift
        public var collapseSplitSpread: CollapseSplitSpread

        public init(
            split: DelayedSpring,
            collapseSplit: DelayedSpring,
            unsplit: SpringConfig,
            unsplitSlide: SpringConfig,
            unsplitAbsorb: Double,
            absorbExpand: Double? = nil,
            absorbExpandCorner: DelayedSpring? = nil,
            joinLead: Double? = nil,
            collapseSplitVia: CollapseSplitVia,
            collapseSplitRise: DelayedSpring,
            collapseSplitLift: CollapseSplitLift,
            collapseSplitSpread: CollapseSplitSpread
        ) {
            self.split = split
            self.collapseSplit = collapseSplit
            self.unsplit = unsplit
            self.unsplitSlide = unsplitSlide
            self.unsplitAbsorb = unsplitAbsorb
            self.absorbExpand = absorbExpand
            self.absorbExpandCorner = absorbExpandCorner
            self.joinLead = joinLead
            self.collapseSplitVia = collapseSplitVia
            self.collapseSplitRise = collapseSplitRise
            self.collapseSplitLift = collapseSplitLift
            self.collapseSplitSpread = collapseSplitSpread
        }
    }

    public struct Press: Sendable, Codable, Equatable {
        public struct IdleRelease: Sendable, Codable, Equatable {
            public var spring: SpringConfig
            public var carry: Double

            public init(spring: SpringConfig, carry: Double) {
                self.spring = spring
                self.carry = carry
            }
        }

        public var down: SpringConfig
        public var up: SpringConfig
        public var swell: SpringConfig
        public var swellTime: Double
        public var decide: Double
        public var release: SpringConfig
        public var idleRelease: IdleRelease?
        /// Width an idle swell leaves behind as it turns back.
        public var idleWiden: IdleWiden?
        public var tapReturn: Double
        public var releaseReturn: Double?
        public var idleTapReturn: Double?
        public var holdReturn: Double
        public var bubbleSwell: SpringConfig?

        public init(
            down: SpringConfig,
            up: SpringConfig,
            swell: SpringConfig,
            swellTime: Double,
            decide: Double,
            release: SpringConfig,
            idleRelease: IdleRelease? = nil,
            idleWiden: IdleWiden? = nil,
            tapReturn: Double,
            releaseReturn: Double? = nil,
            idleTapReturn: Double? = nil,
            holdReturn: Double,
            bubbleSwell: SpringConfig? = nil
        ) {
            self.down = down
            self.up = up
            self.swell = swell
            self.swellTime = swellTime
            self.decide = decide
            self.release = release
            self.idleRelease = idleRelease
            self.idleWiden = idleWiden
            self.tapReturn = tapReturn
            self.releaseReturn = releaseReturn
            self.idleTapReturn = idleTapReturn
            self.holdReturn = holdReturn
            self.bubbleSwell = bubbleSwell
        }
    }
}
