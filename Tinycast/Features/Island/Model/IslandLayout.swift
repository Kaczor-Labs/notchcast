import Foundation
import CoreGraphics

struct IslandSurfaceConfiguration: Equatable, Sendable {
    let notch: CGSize
    let scale: CGFloat

    enum Update { case keep, recreate, deferred }

    func update(from current: Self?, paletteVisible: Bool, hasOverlays: Bool) -> Update {
        guard let current else { return .recreate }
        guard self != current else { return .keep }
        return paletteVisible || hasOverlays ? .deferred : .recreate
    }
}

struct IslandLayout: Sendable {
    let screen: CGRect
    let notch: CGSize
    let canvas: CGSize

    var hasNotch: Bool { notch.width > 0 && notch.height > 0 }
    var top: CGFloat { hasNotch ? -notch.height : 0 }
    var contentTop: CGFloat { hasNotch ? notch.height : 0 }
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
