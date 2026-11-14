import CoreGraphics
import IslandCore

/// Paints a frame's black shape into `context`, which is in stage coordinates: origin top left,
/// y down, one unit a point. Used by the live view and by the snapshot, so both draw the same way.
///
/// Upstream fills three separate paths in this order, so anti-aliasing at their overlaps matches.
@MainActor
public func paintShape(_ geometry: FrameGeometry, in context: CGContext) {
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    for outline in [geometry.paths.pill, geometry.paths.bridge, geometry.paths.bubble] where !outline.isEmpty {
        context.addPath(outline.cgPath)
        context.fillPath()
    }
}
