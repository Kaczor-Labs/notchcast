import SwiftUI

extension ImageRenderer {
    /// `cgImage` rasterizes lazily on the GPU and comes back without pixels when it drops the frame.
    @MainActor var bitmap: CGImage? {
        var image: CGImage?
        render(rasterizationScale: scale) { size, draw in
            guard let context = CGContext(
                data: nil, width: Int((size.width * scale).rounded(.up)),
                height: Int((size.height * scale).rounded(.up)), bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.scaleBy(x: scale, y: scale)
            draw(context)
            image = context.makeImage()
        }
        return image
    }
}
