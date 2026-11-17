// notchcast-sources: Tinycast/Features/Settings/SettingsTab.swift Tinycast/Features/Settings/SettingsAnchor.swift
// notchcast-sources: Tinycast/Features/Settings/SettingsSearchCatalog.swift
// notchcast-sources: Tinycast/Features/Launcher/Model/SearchRelevance.swift Tinycast/Platform/LocalizedResource.swift
// notchcast-sources: Tinycast/Features/Settings/AppAppearance.swift
// notchcast-sources: Tinycast/Features/Notchcast/Hidden/NotchcastIslandPins.swift
import Foundation

@main
@MainActor
struct NotchcastSettingsSearchTests {
    static var failures = 0

    static func check(_ name: String, _ value: Bool) {
        if !value { failures += 1; print("FAIL \(name)") }
    }

    static func finds(_ query: String, _ title: String) -> Bool {
        SettingsSearchCatalog.results(for: query).contains { $0.title == title }
    }

    static func main() {
        let shots = NotchcastSwitch(id: "shots", title: "Screenshots", subtitle: "Grab an area", category: .capture)
        let awake = NotchcastSwitch(id: "awake", title: "Keep awake", subtitle: "Stay on", category: .power)
        NotchcastSettingsSearch.install([awake, shots], commandWords: ["shots": ["Capture area", "grab"]])
        let rows = SettingsSearchCatalog.entries.filter { $0.tab == .notchcast }

        let titles = ["Notchcast", "Show in screenshots and videos", "Outline when open",
                      "Position on displays without a notch", "Screenshots", "Keep awake"]
        check("the pane comes first, then the island rows, then one row per switch", rows.map(\.title) == titles)
        check("the pane row has no anchor", rows.first?.anchor == nil)
        check("the capture row lands on the island section", rows[1].anchor == NotchcastSettingsSearch.island)
        check("the outline row lands on the island section", rows[2].anchor == NotchcastSettingsSearch.island)
        check("the position row lands on the island section", rows[3].anchor == NotchcastSettingsSearch.island)
        check("keyline finds the outline row", finds("keyline", "Outline when open"))
        check("menu bar finds the position row", finds("menu bar", "Position on displays without a notch"))
        check("notch finds the position row", finds("notch", "Position on displays without a notch"))
        check("screen recording finds the capture row", finds("screen recording", "Show in screenshots and videos"))
        check("a switch row lands on its category section", rows[4].anchor == NotchcastSettingsSearch.anchor(.capture))
        check("the section anchor is the category header", rows[5].anchor?.title == NotchcastCategory.power.title)
        check("rows follow category order, not install order", rows[4].anchor?.title == NotchcastCategory.capture.title)
        check("a row's breadcrumb names the category", rows[4].breadcrumb == "Notchcast › \(NotchcastCategory.capture.title)")
        check("a command's name finds its switch", finds("capture area", "Screenshots"))
        check("a subtitle finds its switch", finds("stay on", "Keep awake"))
        check("the island keyword still finds the pane", SettingsSearchCatalog.results(for: "island").first?.anchor == nil)
        if failures > 0 { exit(1) }
        print("PASSED")
    }
}
