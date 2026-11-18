// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandLevelDwell.swift
// notchcast-sources: Tinycast/Features/Island/Model/PillMenuRows.swift Tinycast/Features/Calendar/Model/*.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandController+Accessibility.swift
import Foundation

// The shipped accessibility extension compiled against just the state it reads.
final class PalettePanel { var isVisible = false }

final class IslandController {
    var panel: PalettePanel?
    var level: IslandLevel?
    var notice: IslandNotice?
    var glance: IslandGlance?
    var statuses: [IslandStatus] = []
}

// #867: VoiceOver reads the level exactly as the pill paints it.
@main
struct IslandLevelSpokenTest {
    static func main() {
        let island = IslandController()
        island.level = IslandLevel(source: "brightness", symbol: "sun.min.fill", label: "Brightness", value: 0.0625)
        precondition(island.accessibilityValue == "Brightness, 6%", "got \(island.accessibilityValue)")
        island.level?.value = 0.125
        precondition(island.accessibilityValue == "Brightness, 13%", "got \(island.accessibilityValue)")
        print("nc-Island-level-spoken-test: ok")
    }
}
