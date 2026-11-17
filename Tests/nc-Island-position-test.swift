// notchcast-sources: -package-name IslandEngine -module-name IslandCore
// notchcast-sources: notchcast/vendor/IslandEngine/Sources/IslandCore/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandLayout.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandLayout+Engine.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPosition.swift
import CoreGraphics
import Foundation

@main
enum IslandPositionTest {
    static let screen = CGRect(x: -3440, y: 200, width: 3440, height: 1440)
    static let canvas = CGSize(width: 1100, height: 860)
    static let pill = CGSize(width: 96, height: 24)

    static func layout(_ position: IslandPosition, notch: CGSize = .zero, menuBar: CGFloat = 30) -> IslandLayout {
        IslandLayout(screen: screen, notch: notch, canvas: canvas, position: position, menuBar: menuBar,
                     pill: pill.height)
    }

    static let launcher = CGSize(width: 750, height: 475)

    /// The engine's shapes for the layout, with the tops the island controller hands it.
    static func shapes(_ layout: IslandLayout, rest: CGSize) -> [PresentationKind: ShapeTarget] {
        var metrics = IslandMetrics.standard
        metrics.screen = .init(width: canvas.width, height: canvas.height)
        layout.applyTops(to: &metrics)
        metrics.idle = .init(width: rest.width, height: rest.height)
        metrics.compact.height = rest.height
        metrics.expanded.minHeight = pill.height
        metrics.expanded.maxHeight = canvas.height
        let measure = ContentMeasure(leading: 60, trailing: 40, expandedHeight: launcher.height)
        return Dictionary(uniqueKeysWithValues: [PresentationKind.idle, .compact, .expanded].map {
            ($0, ShapeTarget($0, measure: measure, screenWidth: 750, metrics: metrics))
        })
    }

    static func expect(_ ok: Bool, _ message: String) {
        guard ok else { print("FAIL \(message)"); exit(1) }
    }

    static func main() {
        let expected: [(IslandPosition, CGFloat)] = [(.topEdge, 0), (.menuBarCenter, 3), (.menuBarBottom, 6)]
        for (position, drop) in expected {
            let layout = layout(position)
            expect(layout.top == drop, "\(position) pill top \(layout.top), want \(drop) on a 30 pt bar")
            let shapes = shapes(layout, rest: pill)
            let rest = layout.window.maxY - shapes[.idle]!.top
            expect(rest == screen.maxY - drop, "\(position) rest pill top \(rest) in screen points")
            expect(shapes[.compact]!.top == shapes[.idle]!.top, "\(position) glance top moved from rest")
            expect(shapes[.expanded]!.top == shapes[.idle]!.top,
                   "\(position) expanded top \(shapes[.expanded]!.top) jumps from rest \(shapes[.idle]!.top)")
            let opened = layout.contentFrame(launcher).offsetBy(dx: layout.window.minX, dy: layout.window.minY)
            expect(opened.maxY == rest, "\(position) launcher top \(opened.maxY), rest pill top \(rest)")
            expect(layout.openingTop == rest, "\(position) overlays hang from \(layout.openingTop), not \(rest)")
            let open = shapes[.expanded]!
            let contentTop = layout.window.maxY - (open.top + open.height - launcher.height)
            expect(contentTop == opened.maxY, "\(position) engine content top \(contentTop), launcher \(opened.maxY)")
        }
        expect(IslandPosition.menuBarCenter.drop(menuBar: 37, pill: 24) == 6, "odd room rounds down to whole points")
        for position in IslandPosition.allCases {
            expect(position.drop(menuBar: 0, pill: 24) == 0, "\(position) with a hidden menu bar stays at the edge")
        }

        let notch = CGSize(width: 185, height: 32)
        let notched = layout(.topEdge, notch: notch, menuBar: 32)
        for position in IslandPosition.allCases {
            let layout = layout(position, notch: notch, menuBar: 32)
            expect(layout.top == notched.top && layout.top == -notch.height, "\(position) moved a notched pill")
            expect(layout.openingTop == screen.maxY - notch.height, "\(position) moved a notched opening top")
            let shapes = shapes(layout, rest: CGSize(width: notch.width, height: notch.height * 2))
            expect(shapes[.expanded]!.top == shapes[.idle]!.top, "\(position) notched expanded top jumps")
        }

        let current = IslandSurfaceConfiguration(notch: .zero, top: 0, scale: 1)
        let moved = IslandSurfaceConfiguration(notch: .zero, top: 3, scale: 1)
        expect(moved.update(from: current, paletteVisible: false, hasOverlays: false, animating: false) == .recreate,
               "a new pill top rebuilds the engine surface")
        for (palette, overlays) in [(true, false), (false, true), (false, false)] {
            expect(moved.update(from: current, paletteVisible: palette, hasOverlays: overlays, animating: true)
                   == .deferred, "a pill top moved mid-animation (palette \(palette), overlays \(overlays)) must wait")
        }
        expect(current.update(from: current, paletteVisible: false, hasOverlays: false, animating: true) == .keep,
               "an unchanged surface is kept while animating")
        expect(moved.update(from: nil, paletteVisible: false, hasOverlays: false, animating: true) == .recreate,
               "the first surface is built even while a frame is pending")
        print("PASS IslandPosition drops 0/3/6 on a 30 pt bar, one anchor at rest and open, notch ignores it")
    }
}
