// notchcast-sources: -package-name IslandEngine -module-name IslandCore
// notchcast-sources: notchcast/vendor/IslandEngine/Sources/IslandCore/*.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandSurface+Expand.swift
import Foundation

@MainActor
@main
struct IslandExpandOrderTest {
    static func main() {
        let glance = IslandPresentation<CGSize>.compact(
            CompactContent(leading: CGSize(width: 40, height: 0), trailing: CGSize(width: 40, height: 0)))
        let palette = CGSize(width: 760, height: 420)
        let meeting = CGSize(width: 520, height: 120)
        let cases: [(String, IslandPresentation<CGSize>, String, Double, CGSize, String)] = [
            ("the palette opening from the glance", glance, "glance", 680, palette, "palette"),
            ("the meeting expanding from the glance", glance, "glance", 680, meeting, "expansion"),
            ("the palette opening over the meeting", .expanded(.init(bottom: meeting)), "expansion", 520, palette,
             "palette"),
            ("the palette closing to the meeting", .expanded(.init(bottom: palette)), "palette", 760, meeting,
             "expansion"),
        ]
        for (name, start, key, stage, target, targetKey) in cases {
            let wall = Wall()
            let surface = IslandSurface<CGSize>(presentation: start, contentKey: key,
                clock: FrameClock(wall: { wall.now }), metrics: metrics, motion: .standard, dpr: 2, reduced: false,
                keyline: 0, stageWidth: stage, measure: measure)
            wall.now = 2000
            let now = wall.now
            let before = surface.stage.shape(at: now).pill
            surface.expand(to: target, contentKey: targetKey)
            let first = surface.stage.shape(at: now + 16).pill
            let end = surface.stage.shape(at: now + 3000).pill
            let travel = max(abs(end.width - before.width), abs(end.height - before.height))
            let jump = max(abs(first.width - before.width), abs(first.height - before.height))
            let path = "\(Int(before.width))×\(Int(before.height)) → 16 ms \(Int(first.width))×\(Int(first.height))"
                + " → rest \(Int(end.width))×\(Int(end.height))"
            print("\(name): \(path)")
            precondition(travel > 50, "\(name) changes the shape")
            precondition(jump < travel / 2, "\(name) springs instead of snapping on its first frame: \(path)")
            precondition(surface.stageWidth == target.width && surface.contentKey == targetKey,
                         "\(name) ends on its own stage and content")
        }
        print("IslandExpandOrderTest passed")
    }

    final class Wall {
        var now = 0.0
    }

    static var metrics: IslandMetrics {
        var metrics = IslandMetrics.standard
        metrics.screen = .init(width: 1512, height: 900)
        return metrics
    }

    static func measure(_ presentation: IslandPresentation<CGSize>, _: Double) -> ContentMeasures {
        switch presentation {
        case .expanded(let content): ContentMeasures(expandedHeight: Double(content.bottom?.height ?? 0))
        case .compact(let content):
            ContentMeasures(leading: Double(content.leading?.width ?? 0), trailing: Double(content.trailing?.width ?? 0))
        default: ContentMeasures()
        }
    }
}
