// notchcast-sources: -package-name IslandEngine notchcast/vendor/IslandEngine/Sources/IslandCore/*.swift
// notchcast-reads: notchcast/vendor/IslandEngine/REVISION
import Foundation

@main
enum IslandEngineTests {
    static func close(_ actual: Double, _ expected: Double) {
        precondition(abs(actual - expected) <= 1e-9 * max(1, abs(expected)), "\(actual) != \(expected)")
    }

    static func main() {
        let spring = solveSpring(
            SpringConfig(response: 0.46, dampingFraction: 1.5, blendDuration: 0.05),
            x0: -57.296939846128225, v0: 1921.1778063327074, t: 1.8419387640897185)
        close(spring.x, -0.0002804989659694778)
        close(spring.v, 0.0014634504441383817)
        let idle = ShapeTarget(.idle, measure: .empty, screenWidth: 360, metrics: .standard)
        close(idle.left, -47.425)
        close(idle.right, 47.425)
        close(idle.top, 13.91)
        close(idle.height, 36.84)
        close(idle.radius, 18.42)
        let compact = ShapeTarget(.compact, measure: ContentMeasure(
            leading: 85.05258858669549, trailing: 192.03859576955438),
            screenWidth: 360, metrics: .standard)
        close(compact.left, -126.425)
        close(compact.right, 126.675)
        close(compact.height, 36.85)
        print("PASS: Island engine, 10 spring and outline values")
    }
}
