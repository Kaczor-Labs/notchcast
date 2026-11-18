import AppKit
import SwiftUI

extension EnvironmentValues {
    /// The palette and every dialog sit on the island's black, so its own capsule, glass and scrim stay unpainted.
    @Entry var paletteOnIsland = false
    /// The palette's display has the Frosted look, so island fills let its glass show.
    @Entry var islandFrosted = false
    /// Text on a selection slab or a wash, which costs Frosted inks their 4.5:1.
    @Entry var islandInkLifted = false
    /// #898 prototype: how a Frosted control floating over the list covers the rows under it.
    @Entry var islandFloatingFill = IslandFloatingFill.blur
}

/// #898 prototype: option (b) paints the solid glass, option (d) blurs the rows within the window.
enum IslandFloatingFill: Sendable {
    case solid
    case blur
}

extension Color {
    /// This token on the Frosted look; `lifted` is its ink where `islandInkLifted` is set.
    func frosted(_ value: Color, lifted: Color? = nil) -> Color {
        Color(IslandLookStyle(black: self, frosted: value, lifted: lifted ?? value))
    }
}

extension Color {
    /// `NSColor(_:)` resolves no environment, so AppKit ink would always take Black's value.
    func nsColor(in environment: EnvironmentValues) -> NSColor {
        environment.islandFrosted ? NSColor(Color(resolve(in: environment))) : NSColor(self)
    }

    /// Engine art has no SwiftUI environment, so it names the look of the island it draws on.
    func islandInk(frosted: Bool) -> NSColor {
        var environment = EnvironmentValues()
        environment.colorScheme = .dark
        environment.islandFrosted = frosted
        return nsColor(in: environment)
    }
}

/// Black resolves the token it always was, so nothing outside a Frosted island changes.
private struct IslandLookStyle: ShapeStyle, Hashable {
    let black: Color
    let frosted: Color
    let lifted: Color

    func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        guard environment.islandFrosted else { return black.resolve(in: environment) }
        return (environment.islandInkLifted ? lifted : frosted).resolve(in: environment)
    }
}

enum IslandPaletteSurface {
    /// The island sizes its black from the panel frame, so only stock glass gets room for its rim.
    static func renderingOutset(collapsed: Bool, stock: Bool) -> CGFloat {
        collapsed && stock ? Theme.Size.paletteGlassOutset : 0
    }
}

extension View {
    /// Liquid Glass would ring each island control in light, so on the island it paints the black.
    func islandGlass(_ glass: Glass, in shape: some Shape) -> some View {
        modifier(IslandGlass(glass: glass, shape: shape))
    }
}

private struct IslandGlass<S: Shape>: ViewModifier {
    let glass: Glass
    let shape: S
    @Environment(\.paletteOnIsland) private var onIsland
    @Environment(\.islandFrosted) private var frosted

    func body(content: Content) -> some View {
        content
            .background { if onIsland, !frosted { shape.fill(NotchTheme.Colors.islandSurface) } }
            .overlay {
                if onIsland, frosted {
                    shape.stroke(NotchTheme.Frosted.controlEdge, lineWidth: 2).clipShape(shape)
                }
            }
            .glassEffect(onIsland ? .identity : glass, in: shape)
    }
}

extension View {
    /// The footer capsule and menu circle float over scrolling rows, so on Frosted they cover them.
    func floatingFrosted(in shape: some Shape) -> some View {
        modifier(IslandFloatingGlass(shape: shape)).frosted(in: shape)
    }
}

private struct IslandFloatingGlass<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.paletteOnIsland) private var onIsland
    @Environment(\.islandFrosted) private var frosted
    @Environment(\.islandFloatingFill) private var fill
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.background {
            if onIsland, frosted {
                if fill == .solid || reduceTransparency || contrast == .increased {
                    shape.fill(NotchTheme.Colors.islandGlassSolid)
                } else {
                    IslandRowBlur(shape: shape).overlay(shape.fill(NotchTheme.Colors.islandGlassTint))
                }
            }
        }
    }
}

/// Blurs this window's own rows under the control; the backdrop's glass lives in another window.
private struct IslandRowBlur<S: Shape>: NSViewRepresentable {
    let shape: S

    func makeNSView(context: Context) -> IslandMaskedBlur { IslandMaskedBlur(blending: .withinWindow) }

    func updateNSView(_ view: IslandMaskedBlur, context: Context) {
        let shape = shape
        view.outline = { shape.path(in: $0).cgPath }
    }
}

extension View {
    /// A menu's backing: the island black, or Frosted's denser menu glass and edge.
    func islandMenuBacking(in shape: some Shape) -> some View {
        background { IslandMenuBacking(shape: shape) }
    }
}

private struct IslandMenuBacking<S: Shape>: View {
    let shape: S
    @Environment(\.islandFrosted) private var frosted
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if !frosted {
            shape.fill(NotchTheme.Colors.islandSurface)
        } else {
            Group {
                if reduceTransparency || contrast == .increased {
                    shape.fill(NotchTheme.Colors.islandGlassSolid)
                } else {
                    IslandMenuBlur(shape: shape).overlay(shape.fill(NotchTheme.Frosted.menuTint))
                }
            }
            // The menu clips to its shape, so half of this line is the 1 pt edge inside it.
            .overlay(shape.stroke(NotchTheme.Colors.islandEdge, lineWidth: 2))
        }
    }
}

/// A blur masked to a SwiftUI shape, since an `NSVisualEffectView` ignores SwiftUI clips.
private struct IslandMenuBlur<S: Shape>: NSViewRepresentable {
    let shape: S

    func makeNSView(context: Context) -> IslandMaskedBlur { IslandMaskedBlur(blending: .behindWindow) }

    func updateNSView(_ view: IslandMaskedBlur, context: Context) {
        let shape = shape
        view.outline = { shape.path(in: $0).cgPath }
    }
}

private final class IslandMaskedBlur: NSView {
    private let blur = NSVisualEffectView()
    private let mask = CAShapeLayer()
    var outline: ((CGRect) -> CGPath)? {
        didSet { needsLayout = true }
    }

    init(blending: NSVisualEffectView.BlendingMode) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.mask = mask
        blur.material = .hudWindow
        blur.blendingMode = blending
        blur.state = .active
        blur.autoresizingMask = [.width, .height]
        addSubview(blur)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        mask.frame = bounds
        // SwiftUI draws top-down; this layer's origin is the bottom-left corner.
        var flip = CGAffineTransform(translationX: 0, y: bounds.height).scaledBy(x: 1, y: -1)
        mask.path = outline?(bounds).copy(using: &flip)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
