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
        let keys = NotchcastSwitch(id: "keys", title: "Number keys", subtitle: "Pick a result", category: .keyboardMouse)
        let block = NotchcastSwitch(id: "block", title: "Music block", subtitle: "Stay quiet", category: .music)
        let shots = NotchcastSwitch(id: "shots", title: "Screenshots", subtitle: "Grab an area", category: .capture)
        NotchcastSettingsSearch.install([shots, block, keys], commandWords: ["shots": ["Capture area", "grab"]])
        let rows = SettingsSearchCatalog.entries.filter {
            if case .notchcast = $0.tab { true } else { false }
        }

        let titles = ["Island", "Show in screenshots and videos", "Outline when open",
                      "Position on displays without a notch", "Keyboard & Mouse", "Number keys",
                      "Display & Sound", "Music block", "Capture", "Screenshots"]
        check("one pane row per shown tab, then its rows in tab order", rows.map(\.title) == titles)
        check("a tab with no switch has no row", !rows.contains { $0.tab == .notchcast(.downloads) })
        check("a pane row has no anchor", rows.filter { $0.anchor == nil }.map(\.tab)
              == [.notchcast(.island), .notchcast(.keyboardMouse), .notchcast(.displaySound), .notchcast(.capture)])
        check("the capture row lands on the Island tab's island section",
              rows[1].anchor == NotchcastSettingsSearch.island && rows[1].anchor?.tab == .notchcast(.island))
        check("the outline row lands on the Island tab's island section",
              rows[2].anchor == NotchcastSettingsSearch.island && rows[2].anchor?.tab == .notchcast(.island))
        check("the position row lands on the Island tab's island section",
              rows[3].anchor == NotchcastSettingsSearch.island && rows[3].anchor?.tab == .notchcast(.island))
        check("keyline finds the outline row", finds("keyline", "Outline when open"))
        check("dark no longer finds the outline row", !finds("dark", "Outline when open"))
        check("menu bar finds the position row", finds("menu bar", "Position on displays without a notch"))
        check("notch finds the position row", finds("notch", "Position on displays without a notch"))
        check("screen recording finds the capture row", finds("screen recording", "Show in screenshots and videos"))
        check("the Screenshots switch lands in the Capture tab",
              rows[9].anchor == NotchcastSettingsSearch.anchor(.capture) && rows[9].anchor?.tab == .notchcast(.capture))
        check("a switch row lands on its own tab's category section",
              rows[5].anchor?.tab == .notchcast(.keyboardMouse) && rows[7].anchor?.tab == .notchcast(.displaySound))
        check("a row's breadcrumb names the tab and section",
              rows[7].breadcrumb == "Display & Sound › \(NotchcastCategory.music.title)")
        check("a command's name finds its switch", finds("capture area", "Screenshots"))
        check("a subtitle finds its switch", finds("stay quiet", "Music block"))
        check("the notch keyword finds the Island tab",
              SettingsSearchCatalog.results(for: "notch").first?.tab == .notchcast(.island))
        check("the island keyword finds the Island tab", SettingsSearchCatalog.results(for: "island").first?.anchor == nil)
        if failures > 0 { exit(1) }
        print("PASSED")
    }
}
