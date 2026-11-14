import Foundation
import CoreGraphics

struct IslandOverlayLayout: Sendable {
    let screen: CGRect
    let contentTop: CGFloat
    let palette: CGRect?

    func question(_ size: CGSize) -> CGRect {
        CGRect(x: screen.midX - size.width / 2, y: contentTop - 16 - size.height,
               width: size.width, height: size.height)
    }

    func reports(_ sizes: [CGSize], question: CGRect?) -> [CGRect] {
        var top = min(palette?.minY ?? contentTop, question?.minY ?? contentTop) - 12
        return sizes.map { size in
            let frame = CGRect(x: screen.midX - size.width / 2, y: top - size.height,
                               width: size.width, height: size.height)
            top = frame.minY - 12
            return frame
        }
    }

    func surface(_ frames: [CGRect]) -> CGSize? {
        guard let bounds = frames.reduce(nil as CGRect?, { $0?.union($1) ?? $1 }) else { return nil }
        return CGSize(width: max(bounds.width + 32, palette?.width ?? 0), height: contentTop - bounds.minY + 16)
    }
}
