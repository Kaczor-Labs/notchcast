// notchcast-sources: Tinycast/Features/Island/Model/IslandOverlayLayout.swift
import Foundation
import CoreGraphics

@main
struct IslandOverlayLayoutTest {
    static func main() {
        let screen = CGRect(x: -2580, y: -280, width: 2580, height: 1080)
        for notch in [0.0, 32.0] {
            for palette: CGRect? in [nil, CGRect(x: -1665, y: 325 - notch, width: 750, height: 475)] {
                let layout = IslandOverlayLayout(screen: screen, contentTop: screen.maxY - notch, palette: palette)
                let size = CGSize(width: 420, height: 300)
                let question = layout.question(size)
                precondition(question.size == size && question.midX == screen.midX)
                precondition(question.maxY == screen.maxY - notch - 16)
                let sizes = [CGSize(width: 360, height: 56), CGSize(width: 200, height: 140)]
                let reports = layout.reports(sizes, question: question)
                for frame in reports {
                    precondition(!frame.intersects(question))
                    precondition(palette.map { !$0.intersects(frame) } ?? true)
                    precondition(frame.midX == screen.midX)
                }
                precondition(!reports[0].intersects(reports[1]))
                let surface = layout.surface([question] + reports)!
                precondition(surface.width >= question.width + 32)
                precondition(surface.height >= screen.maxY - notch - reports.last!.minY)
                let plainReports = layout.reports(sizes, question: nil)
                precondition(plainReports[0].maxY == (palette?.minY ?? screen.maxY - notch) - 12)
            }
        }
        precondition(IslandOverlayLayout(screen: screen, contentTop: 800, palette: nil).surface([]) == nil)
        print("PASS IslandOverlayLayout questions and reports never intersect, preserve size, and grow the backdrop")
    }
}
