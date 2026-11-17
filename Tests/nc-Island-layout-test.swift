// notchcast-sources: Tinycast/Features/Island/Model/IslandLayout.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPosition.swift
import Foundation
import CoreGraphics

@main
struct IslandLayoutTest {
    static func main() {
        let current = IslandSurfaceConfiguration(notch: .zero, top: 0, scale: 1)
        for visible in [false, true] {
            for overlays in [false, true] {
                precondition(current.update(from: nil, paletteVisible: visible, hasOverlays: overlays) == .recreate)
                precondition(current.update(from: current, paletteVisible: visible, hasOverlays: overlays) == .keep)
                for next in [IslandSurfaceConfiguration(notch: CGSize(width: 180, height: 32), top: -32, scale: 1),
                             IslandSurfaceConfiguration(notch: .zero, top: 6, scale: 1),
                             IslandSurfaceConfiguration(notch: .zero, top: 0, scale: 2)] {
                    precondition(next.update(from: current, paletteVisible: visible, hasOverlays: overlays)
                        == (visible || overlays ? .deferred : .recreate))
                }
            }
        }
        let notches = [CGSize.zero, CGSize(width: 180, height: 32)]
        for (notch, position) in notches.flatMap({ notch in IslandPosition.allCases.map { (notch, $0) } }) {
            let layout = IslandLayout(screen: CGRect(x: -2580, y: 100, width: 2580, height: 1080),
                                      notch: notch, canvas: CGSize(width: 1100, height: 860),
                                      position: position, menuBar: 30, pill: 24)
            precondition(layout.window.maxY == layout.screen.maxY)
            for scale in [1.0, 1.1, 1.2] {
                let size = CGSize(width: (750 * scale).rounded(), height: (475 * scale).rounded())
                let frame = layout.contentFrame(size)
                precondition(frame.midX == layout.canvas.width / 2)
                precondition(frame.maxY == layout.canvas.height - layout.contentTop)
                let panel = frame.offsetBy(dx: layout.window.minX, dy: layout.window.minY)
                for flipped in [false, true] {
                    let transform = layout.maskTransform(width: size.width, panel: panel, flipped: flipped)
                    for point in [CGPoint.zero, CGPoint(x: 30, y: 12), CGPoint(x: size.width, y: size.height)] {
                        let background = point.applying(layout.stageTransform(width: size.width))
                        let local = point.applying(transform)
                        let global = CGPoint(x: panel.minX + local.x,
                                             y: flipped ? panel.maxY - local.y : panel.minY + local.y)
                        precondition(abs(global.x - background.x - layout.window.minX) < 0.000001)
                        precondition(abs(global.y - background.y - layout.window.minY) < 0.000001)
                    }
                }
            }
            precondition(layout.enginePoint(CGPoint(x: 550, y: 860), stageWidth: 750) == CGPoint(x: 375, y: 0))
        }
        print("PASS IslandLayout anchoring, scale, notch, content conversion and deferred surface recreation")
    }
}
