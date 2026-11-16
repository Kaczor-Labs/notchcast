import CoreGraphics
import IslandCore

extension IslandSurface<CGSize> {
    /// Show first: a resize that leaves the shape alone keeps the old width, and the show snaps.
    func expand(to size: CGSize, contentKey: String) {
        show(.expanded(.init(bottom: size)), contentKey: contentKey)
        resize(stageWidth: size.width, animate: true)
    }
}
