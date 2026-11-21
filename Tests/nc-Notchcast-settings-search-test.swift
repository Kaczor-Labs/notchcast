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
        let block = NotchcastSwitch(id: "block", title: "Music block", subtitle: "Stay quiet", category: .sound)
        let shots = NotchcastSwitch(id: "shots", title: "Screenshots", subtitle: "Grab an area", category: .capture)
        let pages = NotchcastSwitch(id: "pages", title: "Agents page", subtitle: "", category: .islandPages)
        let plain = NotchcastSwitch(id: "plain", title: "Paste Plain Text", subtitle: "", category: .clipboard)
        let distill = NotchcastSwitch(id: "distill", title: "Distill", subtitle: "", category: .downloads)
        let timestamps = NotchcastSwitch(id: "timestamps", title: "Distill Timestamps", subtitle: "Include time codes",
                                         category: .downloads, dependencies: ["distill"])
        let torrents = NotchcastSwitch(id: "torrents", title: "Torrents", subtitle: "", category: .downloads)
        let bond = NotchcastSwitch(id: "bond", title: "Use Wi-Fi and a plugged-in iPhone together", subtitle: "",
                                   category: .downloads, listedWhenAnyEnabled: ["torrents"])
        NotchcastSettingsSearch.install(
            [shots, block, keys, pages, plain, distill, timestamps, torrents, bond],
            commandWords: ["shots": ["Capture area", "grab"]], optionWords: ["distill": ["Markdown folder"]])
        let rows = SettingsSearchCatalog.entries.filter {
            if case .notchcast = $0.tab { true } else { false }
        }
        let titles = [
            "Island", "Show in screenshots and videos", "Outline when open", "Open on hover",
            "Position on displays without a notch", "Look", "Island Content", "Agents page", "Keyboard & Mouse",
            "Number keys", "Display & Sound", "Music block", "Capture", "Screenshots",
            "Clipboard & Files", "Paste Plain Text", "Downloads", "Distill", "Torrents",
        ]
        check("one pane row per shown tab, then its visible main switch rows", rows.map(\.title) == titles)
        check("a tab with no switch has no row", !rows.contains { $0.tab == .notchcast(.launcher) })
        check("a pane row has no anchor", rows.filter { $0.anchor == nil }.map(\.tab) == [
            .notchcast(.island), .notchcast(.islandContent), .notchcast(.keyboardMouse), .notchcast(.displaySound),
            .notchcast(.capture), .notchcast(.clipboardFiles), .notchcast(.downloads),
        ])
        check("the island rows use the Island section", rows.dropFirst().prefix(4).allSatisfy {
            $0.anchor == NotchcastSettingsSearch.island
        })
        check("the look row lands on the Island tab's Look section",
              rows.first { $0.title == "Look" }?.anchor == NotchcastSettingsSearch.look)
        check("frosted finds the look row", finds("frosted", "Look"))
        check("keyline finds the outline row", finds("keyline", "Outline when open"))
        check("dark no longer finds the outline row", !finds("dark", "Outline when open"))
        check("hover finds the hover row", finds("hover", "Open on hover"))
        check("menu bar finds the position row", finds("menu bar", "Position on displays without a notch"))
        check("screen recording finds the capture row", finds("screen recording", "Show in screenshots and videos"))
        check("the Screenshots switch lands in the Capture tab",
              rows.first { $0.title == "Screenshots" }?.anchor == NotchcastSettingsSearch.anchor(.capture))
        check("the Paste Plain Text switch lands in Clipboard & Files",
              SettingsSearchCatalog.results(for: "Paste Plain Text").first?.tab == .notchcast(.clipboardFiles))
        check("a row's breadcrumb names the tab and section",
              rows.first { $0.title == "Music block" }?.breadcrumb == "Display & Sound › Sound")
        check("a command's name finds its switch", finds("capture area", "Screenshots"))
        check("a subtitle finds its switch", finds("stay quiet", "Music block"))
        let target = SettingsTarget.row(NotchcastSettingsSearch.anchor(.downloads), "Distill")
        check("a dependent switch's name lands on the listed parent",
              SettingsSearchCatalog.results(for: "Distill Timestamps").first?.target == target)
        check("dependent subtitles find the parent", finds("include time codes", "Distill"))
        check("option names land on the listed parent",
              SettingsSearchCatalog.results(for: "Markdown folder").contains { $0.target == target })
        check("a conditional switch finds a visible parent",
              SettingsSearchCatalog.results(for: "plugged-in iPhone").contains {
                  $0.target == .row(NotchcastSettingsSearch.anchor(.downloads), "Torrents")
              })
        check("cleanup options land on the Clean up text row",
              SettingsSearchCatalog.results(for: "Cleanup prompt").contains {
                  $0.target == .row(.dictationCleanup, "Clean up text")
              })
        check("the notch keyword finds the Island tab",
              SettingsSearchCatalog.results(for: "notch").first?.tab == .notchcast(.island))
        check("the island keyword finds the Island tab", SettingsSearchCatalog.results(for: "island").first?.anchor == nil)
        if failures > 0 { exit(1) }
        print("PASSED")
    }
}
