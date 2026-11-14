import IslandCore
import SwiftUI

struct IslandGrain<Source: View>: View {
    @Environment(\.displayScale) private var scale
    let grain: IslandMetrics.Expanded.Shadow.Grain
    @ViewBuilder let source: () -> Source

    var body: some View {
        if ShadowGrain.changesAlpha(grain) {
            GeometryReader { geometry in
                if let image = image(size: geometry.size) {
                    Image(decorative: image, scale: scale)
                        .interpolation(.none)
                        .offset(x: -300, y: -300)
                } else {
                    source()
                }
            }
        } else {
            source()
        }
    }

    private func image(size: CGSize) -> CGImage? {
        let renderer = ImageRenderer(content: source().frame(width: size.width, height: size.height).padding(300))
        renderer.scale = scale
        guard let image = renderer.cgImage,
            let context = CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
            let data = context.data
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        let origin = Int((300 * scale).rounded())
        for y in 0..<image.height {
            for x in 0..<image.width {
                let i = (y * image.width + x) * 4
                if pixels[i + 3] == 0 { continue }
                let tx = ((x - origin) % 32 + 32) % 32
                let ty = ((y - origin) % 32 + 32) % 32
                pixels[i + 3] = ShadowGrain.alpha(pixels[i + 3], noise: ShadowGrain.alpha[ty * 32 + tx], grain: grain)
            }
        }
        return context.makeImage()
    }
}
