// notchcast-sources: Tinycast/Features/Notchcast/MacTweaks/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/MacTweaks/Settings/MacTweaksFinderLabels.swift
import Foundation

@main
struct MacTweaksSettingsTest {
    static func main() {
        for tweak in MacTweakCatalog.finder {
            precondition(tweak.finderTitle.key != tweak.id, "\(tweak.id) has no row title")
        }

        let snapshot = MacTweakSnapshot(states: ["path-bar": .applied], journaled: ["path-bar"])
        var page = MacTweaksPageState()
        page.received(snapshot, notice: nil)
        precondition(page.snapshot?.applied == ["path-bar"] && page.notice == nil)

        page.received(nil, notice: "busy")
        precondition(page.snapshot?.applied == ["path-bar"], "A busy reply must keep the counter")
        precondition(page.notice == "busy")

        page.clearNotice()
        page.failed(.read)
        precondition(page.snapshot == nil && page.notice != nil, "A refused read must show a message")

        page.received(snapshot, notice: nil)
        page.failed(.change)
        precondition(page.snapshot == nil && page.notice != nil, "A refused change must show a message")
        print("nc-MacTweaks-settings-test: ok")
    }
}
