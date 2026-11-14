import Foundation
import CoreGraphics

struct IslandOverlayLayout: Sendable {
    let screen: CGRect
    let contentTop: CGFloat
    let palette: CGRect?
    let inset: CGFloat
    let gap: CGFloat

    func question(_ size: CGSize) -> CGRect {
        CGRect(x: screen.midX - size.width / 2, y: contentTop - inset - size.height,
               width: size.width, height: size.height)
    }

    func reports(_ sizes: [CGSize], question: CGRect?) -> [CGRect] {
        var top = min(palette?.minY ?? contentTop, question?.minY ?? contentTop) - gap
        return sizes.map { size in
            let frame = CGRect(x: screen.midX - size.width / 2, y: top - size.height,
                               width: size.width, height: size.height)
            top = frame.minY - gap
            return frame
        }
    }

    func surface(_ frames: [CGRect]) -> CGSize? {
        guard let bounds = frames.reduce(nil as CGRect?, { $0?.union($1) ?? $1 }) else { return nil }
        return CGSize(width: max(bounds.width + inset * 2, palette?.width ?? 0), height: contentTop - bounds.minY + inset)
    }
}
