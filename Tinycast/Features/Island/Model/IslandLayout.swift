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
    /// The engine's pill top, shared by rest and expanded so nothing jumps between them.
    var top: CGFloat { hasNotch ? -notch.height : drop }
    var contentTop: CGFloat { hasNotch ? notch.height : drop }
    var expandedPadding: CGFloat { contentTop - top }
    /// The screen y every opened surface hangs from: palette, questions and reports.
    var openingTop: CGFloat { screen.maxY - contentTop }
    var window: CGRect {
        CGRect(x: screen.midX - canvas.width / 2, y: screen.maxY - canvas.height,
               width: canvas.width, height: canvas.height)
    }

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
