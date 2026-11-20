import Foundation
import CoreGraphics

struct IslandSurfaceConfiguration: Equatable, Sendable {
    let notch: CGSize
    let top: CGFloat
    let scale: CGFloat

    enum Update { case keep, recreate, deferred }

    /// A rebuild drops the engine's running springs, so it waits for the pill to settle too.
    func update(from current: Self?, paletteVisible: Bool, hasOverlays: Bool, animating: Bool = false) -> Update {
        guard let current else { return .recreate }
        guard self != current else { return .keep }
        return paletteVisible || hasOverlays || animating ? .deferred : .recreate
    }
}

/// The latest configure held back until the island can take it; releasing hands it out once.
struct IslandHold<Value> {
    private var value: Value?

    mutating func hold(_ value: Value) { self.value = value }
    mutating func drop() { value = nil }

    mutating func release(blocked: Bool) -> Value? {
        guard !blocked else { return nil }
        defer { value = nil }
        return value
    }
}

struct IslandLayout: Sendable {
    let screen: CGRect
    let notch: CGSize
    let canvas: CGSize
    /// The rest pill's gap below the screen top without a notch; a notch ignores it.
    let drop: CGFloat

    init(screen: CGRect, notch: CGSize, canvas: CGSize, position: IslandPosition, menuBar: CGFloat, pill: CGFloat) {
        self.screen = screen
        self.notch = notch
        self.canvas = canvas
        drop = position.drop(menuBar: menuBar, pill: pill)
    }

    var hasNotch: Bool { notch.width > 0 && notch.height > 0 }
    var notchWidth: CGFloat? { hasNotch ? notch.width : nil }
    /// The cutout's own corner, a third of its height, as Vorssaint draws a camera-tall strip (#850 D25).
    var notchRadius: CGFloat? { hasNotch ? notch.height * 0.34 : nil }
    /// The engine's pill top, shared by rest and expanded so nothing jumps between them.
    var top: CGFloat { hasNotch ? -notch.height : drop }
    var contentTop: CGFloat { hasNotch ? notch.height : drop }
    var expandedPadding: CGFloat { contentTop - top }
    /// The screen y every opened surface hangs from: palette, questions and reports.
    var openingTop: CGFloat { screen.maxY - contentTop }
    /// Without a notch the x snaps to whole points, so an odd-width screen can't leave the pill on a half point.
    var window: CGRect {
        let x = screen.midX - canvas.width / 2
        return CGRect(x: hasNotch ? x : x.rounded(.down), y: screen.maxY - canvas.height,
                      width: canvas.width, height: canvas.height)
    }

    /// The screen x of an opened surface `width` wide, on the same centre line as the pill.
    func openingX(width: CGFloat) -> CGFloat { window.minX + (canvas.width - width) / 2 }

    func contentFrame(_ size: CGSize) -> CGRect {
        CGRect(x: (canvas.width - size.width) / 2,
               y: canvas.height - contentTop - size.height, width: size.width, height: size.height)
    }

    func enginePoint(_ point: CGPoint, stageWidth: CGFloat) -> CGPoint {
        CGPoint(x: point.x - (canvas.width - stageWidth) / 2, y: canvas.height - point.y)
    }

    func stageTransform(width: CGFloat) -> CGAffineTransform {
        CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: (canvas.width - width) / 2, ty: canvas.height)
    }

    func maskTransform(width: CGFloat, panel: CGRect, flipped: Bool) -> CGAffineTransform {
        var transform = stageTransform(width: width)
        transform.tx -= panel.minX - window.minX
        transform.ty -= panel.minY - window.minY
        if flipped {
            transform.d = 1
            transform.ty = panel.maxY - window.maxY
        }
        return transform
    }
}
