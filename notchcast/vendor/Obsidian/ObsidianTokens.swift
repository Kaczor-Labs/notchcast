// Generated from tokens/tokens.json by scripts/build-tokens.py. Edit tokens.json, not this file.
// OBSIDIAN 2.0.1 (CHANGELOG.md).
// OBSIDIAN tokens for macOS (SwiftUI): one nested enum per tokens/<group>.css, constants named after the CSS
// custom property in camelCase. Where tokens.json gives a mac value it replaces the web one here.
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

public enum ObsidianTokens {
    /// The release these values belong to (CHANGELOG.md in the design-system skill).
    public static let version = "2.0.1"
    /// One CSS box-shadow layer. SwiftUI's .shadow(color:radius:x:y:) takes radius = blur / 2 and has no spread.
    public struct Shadow: Sendable {
        public let color: Color
        public let x: CGFloat
        public let y: CGFloat
        public let blur: CGFloat
        public let spread: CGFloat
        public let inset: Bool
    }

    public enum Palette {
        // Cool neutral ramp: ink to paper (internal — chrome reads themed names)
        public static let gray0 = Color(.sRGB, red: 255.0 / 255, green: 255.0 / 255, blue: 255.0 / 255, opacity: 1) // #ffffff
        public static let gray50 = Color(.sRGB, red: 244.0 / 255, green: 245.0 / 255, blue: 247.0 / 255, opacity: 1) // #f4f5f7
        public static let gray100 = Color(.sRGB, red: 236.0 / 255, green: 238.0 / 255, blue: 241.0 / 255, opacity: 1) // #eceef1
        public static let gray150 = Color(.sRGB, red: 223.0 / 255, green: 225.0 / 255, blue: 229.0 / 255, opacity: 1) // #dfe1e5
        public static let gray200 = Color(.sRGB, red: 207.0 / 255, green: 210.0 / 255, blue: 216.0 / 255, opacity: 1) // #cfd2d8
        public static let gray250 = Color(.sRGB, red: 194.0 / 255, green: 197.0 / 255, blue: 203.0 / 255, opacity: 1) // #c2c5cb
        public static let gray300 = Color(.sRGB, red: 170.0 / 255, green: 176.0 / 255, blue: 185.0 / 255, opacity: 1) // #aab0b9
        public static let gray400 = Color(.sRGB, red: 136.0 / 255, green: 142.0 / 255, blue: 153.0 / 255, opacity: 1) // #888e99
        public static let gray450 = Color(.sRGB, red: 132.0 / 255, green: 136.0 / 255, blue: 143.0 / 255, opacity: 1) // #84888f
        public static let gray500 = Color(.sRGB, red: 95.0 / 255, green: 99.0 / 255, blue: 106.0 / 255, opacity: 1) // #5f636a
        public static let gray600 = Color(.sRGB, red: 71.0 / 255, green: 75.0 / 255, blue: 81.0 / 255, opacity: 1) // #474b51
        public static let gray700 = Color(.sRGB, red: 42.0 / 255, green: 46.0 / 255, blue: 53.0 / 255, opacity: 1) // #2a2e35
        public static let gray800 = Color(.sRGB, red: 22.0 / 255, green: 23.0 / 255, blue: 27.0 / 255, opacity: 1) // #16171b
        public static let gray850 = Color(.sRGB, red: 19.0 / 255, green: 20.0 / 255, blue: 23.0 / 255, opacity: 1) // #131417
        public static let gray900 = Color(.sRGB, red: 16.0 / 255, green: 17.0 / 255, blue: 19.0 / 255, opacity: 1) // #101113
        public static let gray925 = Color(.sRGB, red: 11.0 / 255, green: 12.0 / 255, blue: 14.0 / 255, opacity: 1) // #0b0c0e
        public static let gray950 = Color(.sRGB, red: 8.0 / 255, green: 9.0 / 255, blue: 11.0 / 255, opacity: 1) // #08090b
        public static let gray975 = Color(.sRGB, red: 6.0 / 255, green: 7.0 / 255, blue: 9.0 / 255, opacity: 1) // #060709
        // State-hue primitives (theme.css maps them to --green / --yellow / --red)
        public static let greenBright = Color(.sRGB, red: 74.0 / 255, green: 222.0 / 255, blue: 128.0 / 255, opacity: 1) // #4ade80
        public static let amberBright = Color(.sRGB, red: 251.0 / 255, green: 191.0 / 255, blue: 36.0 / 255, opacity: 1) // #fbbf24
        public static let redBright = Color(.sRGB, red: 248.0 / 255, green: 113.0 / 255, blue: 113.0 / 255, opacity: 1) // #f87171
        // Identity palette (policy C — dots / avatars / chart series only)
        public static let deskCos = Color(.sRGB, red: 34.0 / 255, green: 197.0 / 255, blue: 94.0 / 255, opacity: 1) // #22c55e
        public static let projectBlue = Color(.sRGB, red: 77.0 / 255, green: 159.0 / 255, blue: 255.0 / 255, opacity: 1) // #4d9fff
        public static let projectViolet = Color(.sRGB, red: 167.0 / 255, green: 139.0 / 255, blue: 250.0 / 255, opacity: 1) // #a78bfa
        public static let projectMint = Color(.sRGB, red: 52.0 / 255, green: 211.0 / 255, blue: 153.0 / 255, opacity: 1) // #34d399
        public static let projectAmber = Color(.sRGB, red: 245.0 / 255, green: 158.0 / 255, blue: 11.0 / 255, opacity: 1) // #f59e0b
        public static let projectPink = Color(.sRGB, red: 236.0 / 255, green: 72.0 / 255, blue: 153.0 / 255, opacity: 1) // #ec4899
        public static let projectSlate = Color(.sRGB, red: 100.0 / 255, green: 116.0 / 255, blue: 139.0 / 255, opacity: 1) // #64748b
        public static let projectSteel = Color(.sRGB, red: 135.0 / 255, green: 148.0 / 255, blue: 163.0 / 255, opacity: 1) // #8794a3
        public static let projectLilac = Color(.sRGB, red: 179.0 / 255, green: 166.0 / 255, blue: 192.0 / 255, opacity: 1) // #b3a6c0
        public static let projectSage = Color(.sRGB, red: 159.0 / 255, green: 173.0 / 255, blue: 149.0 / 255, opacity: 1) // #9fad95
    }

    public enum Theme {
        // Surfaces — black ladder lit from above
        public static let background = Color(.sRGB, red: 6.0 / 255, green: 7.0 / 255, blue: 9.0 / 255, opacity: 1) // #060709
        public static let cardLow = Color(.sRGB, red: 8.0 / 255, green: 9.0 / 255, blue: 11.0 / 255, opacity: 1) // #08090b
        public static let card = Color(.sRGB, red: 11.0 / 255, green: 12.0 / 255, blue: 14.0 / 255, opacity: 1) // #0b0c0e
        public static let popover = Color(.sRGB, red: 16.0 / 255, green: 17.0 / 255, blue: 19.0 / 255, opacity: 1) // #101113
        public static let secondary = Color(.sRGB, red: 19.0 / 255, green: 20.0 / 255, blue: 23.0 / 255, opacity: 1) // #131417
        public static let muted = Color(.sRGB, red: 22.0 / 255, green: 23.0 / 255, blue: 27.0 / 255, opacity: 1) // #16171b
        public static let input = Color(.sRGB, red: 16.0 / 255, green: 17.0 / 255, blue: 19.0 / 255, opacity: 1) // #101113
        // Text — white with distance, never gray-mud
        public static let foregroundStrong = Color(.sRGB, red: 244.0 / 255, green: 245.0 / 255, blue: 247.0 / 255, opacity: 1) // #f4f5f7
        public static let foreground = Color(.sRGB, red: 194.0 / 255, green: 197.0 / 255, blue: 203.0 / 255, opacity: 1) // #c2c5cb
        public static let mutedForeground = Color(.sRGB, red: 132.0 / 255, green: 136.0 / 255, blue: 143.0 / 255, opacity: 1) // #84888f
        public static let foregroundFaint = Color(.sRGB, red: 95.0 / 255, green: 99.0 / 255, blue: 106.0 / 255, opacity: 1) // #5f636a
        public static let foregroundDisabled = Color(.sRGB, red: 71.0 / 255, green: 75.0 / 255, blue: 81.0 / 255, opacity: 1) // #474b51
        public static let fieldPlaceholder = Color(.sRGB, red: 132.0 / 255, green: 136.0 / 255, blue: 143.0 / 255, opacity: 1) // #84888f
        // Lines — light edges, not drawn borders
        public static let border = Color(.sRGB, red: 255.0 / 255, green: 255.0 / 255, blue: 255.0 / 255, opacity: 0.08) // rgb(255 255 255 / 0.08)
        public static let borderStrong = Color(.sRGB, red: 255.0 / 255, green: 255.0 / 255, blue: 255.0 / 255, opacity: 0.14) // rgb(255 255 255 / 0.14)
        public static let borderSubtle = Color(.sRGB, red: 255.0 / 255, green: 255.0 / 255, blue: 255.0 / 255, opacity: 0.05) // rgb(255 255 255 / 0.05)
        public static let borderControl = Color(.sRGB, red: 255.0 / 255, green: 255.0 / 255, blue: 255.0 / 255, opacity: 0.4) // rgb(255 255 255 / 0.40)
        // Accent = light (Halo)
        public static let accent = Color(.sRGB, red: 255.0 / 255, green: 255.0 / 255, blue: 255.0 / 255, opacity: 1) // #ffffff (mac; web: #f4f5f7)
        public static let accentEmphasis = Color(.sRGB, red: 255.0 / 255, green: 255.0 / 255, blue: 255.0 / 255, opacity: 1) // #ffffff
        public static let accentForeground = Color(.sRGB, red: 11.0 / 255, green: 12.0 / 255, blue: 14.0 / 255, opacity: 1) // #0b0c0e
        public static let accentDim = Color(.sRGB, red: 255.0 / 255, green: 255.0 / 255, blue: 255.0 / 255, opacity: 0.08) // rgb(255 255 255 / 0.08)
        public static let accentMuted = Color(.sRGB, red: 207.0 / 255, green: 210.0 / 255, blue: 216.0 / 255, opacity: 1) // #cfd2d8
        public static let primary = Color(.sRGB, red: 255.0 / 255, green: 255.0 / 255, blue: 255.0 / 255, opacity: 1) // #ffffff (mac; web: #f4f5f7)
        public static let primaryForeground = Color(.sRGB, red: 11.0 / 255, green: 12.0 / 255, blue: 14.0 / 255, opacity: 1) // #0b0c0e
        public static let ring = Color(.sRGB, red: 244.0 / 255, green: 245.0 / 255, blue: 247.0 / 255, opacity: 0.55) // rgb(244 245 247 / 0.55)
        public static let selection = Color(.sRGB, red: 255.0 / 255, green: 255.0 / 255, blue: 255.0 / 255, opacity: 0.22) // rgb(255 255 255 / 0.22)
        // Elevation — depth from caught light + ink shadow for overlays
        public static let edgeLight = Shadow(color: Color(.sRGB, red: 255.0 / 255, green: 255.0 / 255, blue: 255.0 / 255, opacity: 0.06), x: 0, y: 1, blur: 0, spread: 0, inset: true) // inset 0 1px 0 rgb(255 255 255 / 0.06)
        public static let edgeLightStrong = Shadow(color: Color(.sRGB, red: 255.0 / 255, green: 255.0 / 255, blue: 255.0 / 255, opacity: 0.09), x: 0, y: 1, blur: 0, spread: 0, inset: true) // inset 0 1px 0 rgb(255 255 255 / 0.09)
        public static let edgeLightModal = Shadow(color: Color(.sRGB, red: 255.0 / 255, green: 255.0 / 255, blue: 255.0 / 255, opacity: 0.13), x: 0, y: 1, blur: 0, spread: 0, inset: true) // inset 0 1px 0 rgb(255 255 255 / 0.13)
        public static let shadowSm = Shadow(color: Color(.sRGB, red: 0.0 / 255, green: 0.0 / 255, blue: 0.0 / 255, opacity: 0.4), x: 0, y: 1, blur: 2, spread: 0, inset: false) // 0 1px 2px rgb(0 0 0 / 0.40)
        public static let shadowPopover = Shadow(color: Color(.sRGB, red: 0.0 / 255, green: 0.0 / 255, blue: 0.0 / 255, opacity: 0.6), x: 0, y: 16, blur: 48, spread: 0, inset: false) // 0 16px 48px rgb(0 0 0 / 0.60)
        public static let shadowModal = Shadow(color: Color(.sRGB, red: 0.0 / 255, green: 0.0 / 255, blue: 0.0 / 255, opacity: 0.72), x: 0, y: 28, blur: 90, spread: 0, inset: false) // 0 28px 90px rgb(0 0 0 / 0.72)
        // Washes
        public static let hoverWash = Color(.sRGB, red: 255.0 / 255, green: 255.0 / 255, blue: 255.0 / 255, opacity: 0.04) // rgb(255 255 255 / 0.04)
        public static let activeWash = Color(.sRGB, red: 255.0 / 255, green: 255.0 / 255, blue: 255.0 / 255, opacity: 0.06) // rgb(255 255 255 / 0.06)
        public static let overlayBackdrop = Color(.sRGB, red: 0.0 / 255, green: 0.0 / 255, blue: 0.0 / 255, opacity: 0.72) // rgb(0 0 0 / 0.72)
        public static let scrollbarThumb = Color(.sRGB, red: 255.0 / 255, green: 255.0 / 255, blue: 255.0 / 255, opacity: 0.28) // rgb(255 255 255 / 0.28)
        public static let opacityDisabled: Double = 0.45
        // Semantic — state only. The -dim / -border triplets are the tone's own rgb; regenerate them when the tone changes.
        public static let green = Color(.sRGB, red: 74.0 / 255, green: 222.0 / 255, blue: 128.0 / 255, opacity: 1) // #4ade80
        public static let greenDim = Color(.sRGB, red: 74.0 / 255, green: 222.0 / 255, blue: 128.0 / 255, opacity: 0.13) // rgb(74 222 128 / 0.13)
        public static let greenBorder = Color(.sRGB, red: 74.0 / 255, green: 222.0 / 255, blue: 128.0 / 255, opacity: 0.3) // rgb(74 222 128 / 0.30)
        public static let yellow = Color(.sRGB, red: 251.0 / 255, green: 191.0 / 255, blue: 36.0 / 255, opacity: 1) // #fbbf24
        public static let yellowDim = Color(.sRGB, red: 251.0 / 255, green: 191.0 / 255, blue: 36.0 / 255, opacity: 0.13) // rgb(251 191 36 / 0.13)
        public static let yellowBorder = Color(.sRGB, red: 251.0 / 255, green: 191.0 / 255, blue: 36.0 / 255, opacity: 0.3) // rgb(251 191 36 / 0.30)
        public static let red = Color(.sRGB, red: 248.0 / 255, green: 113.0 / 255, blue: 113.0 / 255, opacity: 1) // #f87171
        public static let redDim = Color(.sRGB, red: 248.0 / 255, green: 113.0 / 255, blue: 113.0 / 255, opacity: 0.13) // rgb(248 113 113 / 0.13)
        public static let redBorder = Color(.sRGB, red: 248.0 / 255, green: 113.0 / 255, blue: 113.0 / 255, opacity: 0.3) // rgb(248 113 113 / 0.30)
        public static let destructive = Color(.sRGB, red: 248.0 / 255, green: 113.0 / 255, blue: 113.0 / 255, opacity: 1) // #f87171
        public static let destructiveForeground = Color(.sRGB, red: 6.0 / 255, green: 7.0 / 255, blue: 9.0 / 255, opacity: 1) // #060709
        // Charts (identity series — policy C)
        public static let chart1 = Color(.sRGB, red: 255.0 / 255, green: 255.0 / 255, blue: 255.0 / 255, opacity: 1) // #ffffff (mac; web: #f4f5f7)
        public static let chart2 = Color(.sRGB, red: 251.0 / 255, green: 191.0 / 255, blue: 36.0 / 255, opacity: 1) // #fbbf24
        public static let chart3 = Color(.sRGB, red: 176.0 / 255, green: 124.0 / 255, blue: 240.0 / 255, opacity: 1) // #b07cf0
        public static let chart4 = Color(.sRGB, red: 77.0 / 255, green: 159.0 / 255, blue: 255.0 / 255, opacity: 1) // #4d9fff
        public static let chart5 = Color(.sRGB, red: 229.0 / 255, green: 103.0 / 255, blue: 125.0 / 255, opacity: 1) // #e5677d
        public static let chart6 = Color(.sRGB, red: 143.0 / 255, green: 207.0 / 255, blue: 82.0 / 255, opacity: 1) // #8fcf52
        public static let chart7 = Color(.sRGB, red: 236.0 / 255, green: 72.0 / 255, blue: 153.0 / 255, opacity: 1) // #ec4899
        public static let chart8 = Color(.sRGB, red: 126.0 / 255, green: 138.0 / 255, blue: 160.0 / 255, opacity: 1) // #7e8aa0
    }

    public enum Typography {
        // Families (match the app's bundled families)
        public static let fontSans = "Instrument Sans"
        public static let fontDisplay = "Instrument Sans"
        public static let fontMono = "JetBrains Mono"
        // Numeric size scale (px) — the app vocabulary
        public static let textXs: CGFloat = 11
        public static let textSm: CGFloat = 12
        public static let textBase: CGFloat = 13
        public static let textMd: CGFloat = 14
        public static let textLg: CGFloat = 16
        public static let textXl: CGFloat = 18
        public static let text2xl: CGFloat = 20
        public static let text3xl: CGFloat = 24
        public static let text4xl: CGFloat = 32
        public static let text5xl: CGFloat = 40
        // Display roles — web / marketing headlines (extends the product scale)
        public static let displaySm: CGFloat = 48
        public static let displayMd: CGFloat = 60
        public static let displayLg: CGFloat = 72
        public static let displayXl: CGFloat = 96
        // Weights
        public static let fwRegular = Font.Weight.regular
        public static let fwMedium = Font.Weight.medium
        public static let fwSemibold = Font.Weight.semibold
        public static let fwBold = Font.Weight.bold
        // Line heights
        public static let lhTight: Double = 1.05
        public static let lhSnug: Double = 1.2
        public static let lhHeading: Double = 1.25
        public static let lhNormal: Double = 1.5
        public static let lhRelaxed: Double = 1.65
        // Tracking
        public static let trackingTighter: CGFloat = -0.03 // em
        public static let trackingTight: CGFloat = -0.018 // em
        public static let trackingSnug: CGFloat = -0.008 // em
        public static let trackingNormal: CGFloat = 0
        public static let trackingWide: CGFloat = 0.06 // em
        public static let trackingWider: CGFloat = 0.1 // em
        // Numerics — tabular everywhere a number must align
    }

    public enum Spacing {
        // Spacing scale (4px base)
        public static let space1: CGFloat = 4
        public static let space2: CGFloat = 8
        public static let space3: CGFloat = 12
        public static let space4: CGFloat = 16
        public static let space5: CGFloat = 20
        public static let space6: CGFloat = 24
        public static let space7: CGFloat = 32
        public static let space8: CGFloat = 48
        public static let space9: CGFloat = 64
        public static let space10: CGFloat = 80
        // Section rhythm — web / marketing
        public static let space12: CGFloat = 96
        public static let space14: CGFloat = 120
        public static let space16: CGFloat = 160
        public static let pagePad: CGFloat = 24
        public static let spaceHalf: CGFloat = 2
        // Radii — one scale, steps per platform: web 4 / 8 / 12, macOS 10 / 18 / 26. --radius-island (glass) is 26 on both. Pill for chips/switches/dots
        public static let radiusSm: CGFloat = 10 // (mac; web: 4px)
        public static let radius: CGFloat = 18 // (mac; web: 8px)
        public static let radiusMd: CGFloat = 18 // (mac; web: 8px)
        public static let radiusLg: CGFloat = 26 // (mac; web: 12px)
        public static let radiusXl: CGFloat = 16
        public static let radius2xl: CGFloat = 24
        public static let radiusPill: CGFloat = 9999
        // Container max-widths — web layout
        public static let containerSm: CGFloat = 640
        public static let containerMd: CGFloat = 820
        public static let containerLg: CGFloat = 1080
        public static let containerXl: CGFloat = 1240
        public static let container2xl: CGFloat = 1440
        // Control sizing
        public static let controlHSm: CGFloat = 28
        public static let controlH: CGFloat = 32
        public static let controlHLg: CGFloat = 40
        public static let controlHXl: CGFloat = 48
        public static let tapMin: CGFloat = 44
        public static let targetMin: CGFloat = 24
        public static let rowMin: CGFloat = 52
        public static let rowMinDense: CGFloat = 40
        // Component geometry — the literals the grammar needs, named once
        public static let dotSize: CGFloat = 7
        public static let controlIcon: CGFloat = 16
        public static let iconSize: CGFloat = 14
        public static let iconSizeLg: CGFloat = 16
        public static let iconSizeXl: CGFloat = 28
        public static let switchW: CGFloat = 38
        public static let switchH: CGFloat = 22
        public static let switchKnob: CGFloat = 16
        public static let segmentH: CGFloat = 26
        public static let meterH: CGFloat = 6
        public static let avatarSize: CGFloat = 28
        public static let floatMin: CGFloat = 180
        public static let tooltipMax: CGFloat = 240
        public static let toastW: CGFloat = 360
        public static let featureMin: CGFloat = 240
        public static let blurNavbar: CGFloat = 12
        public static let blurBackdrop: CGFloat = 2
        public static let bandMin: CGFloat = 240
        public static let rowLabelMin: CGFloat = 120
        public static let modalSm: CGFloat = 420
        public static let modalMd: CGFloat = 560
        public static let modalLg: CGFloat = 880
        public static let navbarH: CGFloat = 60
        public static let underlineOffset: CGFloat = 3
        public static let textareaMin: CGFloat = 96
        public static let spinnerSize: CGFloat = 16
        public static let tooltipDelay: Double = 0.4 // seconds (mac; web: 700ms)
    }

    public enum Layout {
        // z-index — never cover each other incorrectly
        public static let zBase: Double = 0
        public static let zSticky: Double = 10
        public static let zNav: Double = 20
        public static let zDock: Double = 30
        public static let zPopover: Double = 100
        public static let zModal: Double = 200
        public static let zToast: Double = 300
        public static let zTooltip: Double = 400
        // Breakpoints (reference values; use in @media queries)
        public static let bpSm: CGFloat = 380
        public static let bpMd: CGFloat = 768
        public static let bpLg: CGFloat = 1024
        public static let bpXl: CGFloat = 1440
    }

    public enum Motion {
        public static let transitionFast: Double = 0.12 // seconds (mac; web: 0.10s)
        public static let transitionBase: Double = 0.12 // seconds (mac; web: 0.15s)
        public static let transitionSpring: Double = 0.18 // seconds (mac; web: 0.25s)
        public static let transitionSlow: Double = 0.32 // seconds (mac; web: 0.40s)
        public static let transitionReveal: Double = 0.6 // seconds
        public static let transitionStagger: Double = 0.05 // seconds
        public static let transitionLoop: Double = 1.2 // seconds
        public static let easeDefault: (x1: Double, y1: Double, x2: Double, y2: Double) = (0.2, 0, 0, 1)
        public static let easeOut: (x1: Double, y1: Double, x2: Double, y2: Double) = (0.16, 1, 0.3, 1)
        public static let easeSpring: (x1: Double, y1: Double, x2: Double, y2: Double) = (0.34, 1.56, 0.64, 1)
    }

    public enum Glass {
        // Tints — the fill over --glass-backdrop
        public static let glassBar = Color(.sRGB, red: 24.0 / 255, green: 25.0 / 255, blue: 28.0 / 255, opacity: 0.88) // rgb(24 25 28 / 0.88) (mac; web: rgb(24 25 28 / 0.82))
        public static let glassPane = Color(.sRGB, red: 32.0 / 255, green: 33.0 / 255, blue: 37.0 / 255, opacity: 0.88) // rgb(32 33 37 / 0.88) (mac; web: rgb(32 33 37 / 0.86))
        public static let glassSheet = Color(.sRGB, red: 40.0 / 255, green: 42.0 / 255, blue: 46.0 / 255, opacity: 0.92) // rgb(40 42 46 / 0.92)
        // No-blur solids — used alone where backdrop-filter is unavailable, reduced transparency or increased contrast is on, or the product's own less-transparency switch is set; --glass-sheet-solid is also every web dialog and sheet
        public static let glassBarSolid = Color(.sRGB, red: 28.0 / 255, green: 29.0 / 255, blue: 32.0 / 255, opacity: 1) // #1c1d20 (mac; web: #17181b)
        public static let glassPaneSolid = Color(.sRGB, red: 32.0 / 255, green: 33.0 / 255, blue: 37.0 / 255, opacity: 1) // #202125
        public static let glassSheetSolid = Color(.sRGB, red: 40.0 / 255, green: 41.0 / 255, blue: 45.0 / 255, opacity: 1) // #28292d
        // Backdrop, edge and lift
        #if canImport(AppKit)
        public static let glassBackdropMaterial = NSVisualEffectView.Material.hudWindow // web: blur(36px) brightness(1.3) saturate(1.5)
        #endif
        public static let glassEdge = Color(.sRGB, red: 255.0 / 255, green: 255.0 / 255, blue: 255.0 / 255, opacity: 0.12) // rgb(255 255 255 / 0.12)
        public static let glassRule = Color(.sRGB, red: 255.0 / 255, green: 255.0 / 255, blue: 255.0 / 255, opacity: 0.16) // rgb(255 255 255 / 0.16)
        public static let glassLiftRest = Shadow(color: Color(.sRGB, red: 0.0 / 255, green: 0.0 / 255, blue: 0.0 / 255, opacity: 0.55), x: 0, y: 6, blur: 18, spread: -6, inset: false) // 0 6px 18px -6px rgb(0 0 0 / 0.55)
        public static let glassLiftOpen = Shadow(color: Color(.sRGB, red: 0.0 / 255, green: 0.0 / 255, blue: 0.0 / 255, opacity: 0.75), x: 0, y: 30, blur: 70, spread: -26, inset: false) // 0 30px 70px -26px rgb(0 0 0 / 0.75)
        // Text on glass — three inks only: --foreground-strong, --glass-muted-foreground, --glass-destructive. The page's muted and red tones are too dark over a bright backdrop
        public static let glassMutedForegroundSecondary = Color(.sRGB, red: 255.0 / 255, green: 255.0 / 255, blue: 255.0 / 255, opacity: 0.72) // rgb(255 255 255 / 0.72) (mac secondary; web: #c2c5cb)
        public static let glassMutedForegroundTertiary = Color(.sRGB, red: 255.0 / 255, green: 255.0 / 255, blue: 255.0 / 255, opacity: 0.6) // rgb(255 255 255 / 0.60) (mac tertiary; web: #c2c5cb)
        public static let glassDestructive = Color(.sRGB, red: 255.0 / 255, green: 179.0 / 255, blue: 179.0 / 255, opacity: 1) // #ffb3b3
        // Row and control states on glass. Text on a pressed or cursor row is --foreground-strong: muted and destructive text sit on --glass-hover at most
        public static let glassHover = Color(.sRGB, red: 255.0 / 255, green: 255.0 / 255, blue: 255.0 / 255, opacity: 0.08) // rgb(255 255 255 / 0.08)
        public static let glassPressed = Color(.sRGB, red: 255.0 / 255, green: 255.0 / 255, blue: 255.0 / 255, opacity: 0.14) // rgb(255 255 255 / 0.14)
        public static let glassCursor = Color(.sRGB, red: 255.0 / 255, green: 255.0 / 255, blue: 255.0 / 255, opacity: 0.16) // rgb(255 255 255 / 0.16)
        public static let glassDestructiveWash = Color(.sRGB, red: 248.0 / 255, green: 113.0 / 255, blue: 113.0 / 255, opacity: 0.2) // rgb(248 113 113 / 0.20)
        public static let radiusIsland: CGFloat = 26
    }
}

// No Swift form (CSS-only values): --glow, --glow-top, --feature-numeric, --feature-text
