import IslandCore
import SwiftUI

/// SwiftUI's blur radius for one point of the shadow's standard deviation, measured against Gecko
/// at 3x: Gecko draws the shadow filter's Gaussians narrower than its CSS `blur()`.
let shadowBlurScale = 0.79

/// The expanded island's soft shadow: a broad, faint tail under a key layer, each the shape's
/// alpha blurred, moved down and faded by the stage's slope for this frame.
struct IslandShadow<Source: View>: View {
    let shadow: IslandMetrics.Expanded.Shadow
    let slopes: ContentShadow
    /// What casts the shadow: the keyline and the black shape, drawn as they are.
    @ViewBuilder let source: () -> Source

    var body: some View {
        if slopes.filtered {
            IslandGrain(grain: shadow.grain) {
                ZStack(alignment: .topLeading) {
                    layer(blur: shadow.tail.blur, aspect: shadow.tail.aspect, offsetY: shadow.tail.offsetY)
                        .opacity(slopes.tailSlope)
                    layer(blur: shadow.blur, aspect: shadow.aspect, offsetY: shadow.offsetY)
                        .opacity(slopes.slope)
                }
            }
        }
    }

    /// The source's alpha under a Gaussian `blur / 2` deep and `aspect` times that across, which
    /// SwiftUI's round blur draws on a source squeezed sideways and stretched back after.
    private func layer(blur: Double, aspect: Double, offsetY: Double) -> some View {
        source()
            .colorMultiply(.black)
            .scaleEffect(x: 1 / aspect, y: 1, anchor: .center)
            .blur(radius: blur / 2 * shadowBlurScale)
            .scaleEffect(x: aspect, y: 1, anchor: .center)
            .offset(y: offsetY)
    }
}
