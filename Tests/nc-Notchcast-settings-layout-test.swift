// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/NotchcastCategory.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/NotchcastPane.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/NotchcastSwitch.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/NotchcastSettingsLayout.swift
import Foundation

@main
enum NotchcastSettingsLayoutTests {
    static func item(
        _ id: String, _ category: NotchcastCategory = .display, needs: [String] = [], anyOf: [String] = []
    ) -> NotchcastSwitch {
        NotchcastSwitch(id: id, title: id, subtitle: "", category: category,
                        dependencies: needs, listedWhenAnyEnabled: anyOf)
    }

    static func main() {
        let child = item("child", needs: ["brightness"])
        let grandchild = item("grandchild", needs: ["child"])
        let orphan = item("orphan", needs: ["missing"])
        let loopA = item("loopA", needs: ["loopB"])
        let loopB = item("loopB", needs: ["loopA"])
        let bond = item("bond", .downloads, anyOf: ["fast", "torrents"])
        let switches = [
            item("speaker", .sound), child, item("plain"), item("brightness"),
            grandchild, orphan, loopA, loopB, item("another", .sound, needs: ["speaker", "mic"]),
            item("mic", .sound), item("download", .downloads), item("fast", .downloads, needs: ["download"]),
            bond, item("torrents", .downloads), item("finder", .finder),
        ]
        let layout = NotchcastSettingsLayout(switches: switches)
        func groups(
            _ enabled: Set<String>, in pane: NotchcastPane = .displaySound
        ) -> [NotchcastSettingsLayout.Group] {
            layout.groups(in: pane, isEnabled: enabled.contains, withCommands: ["mic", "brightness", "bond"],
                          withRows: ["brightness", "grandchild"])
        }

        let off = groups([])
        precondition(off.map(\.category) == [.display, .sound], "pane category order")
        precondition(off.map { $0.switches.map(\.id) } == [["plain", "brightness"], ["speaker", "mic"]],
                     "registry order and only main switches across groups")
        precondition(off.allSatisfy { $0.details.isEmpty }, "all off has no detail sections")
        precondition(groups([], in: .clipboardFiles).map(\.category) == [.finder], "empty categories disappear")
        precondition(groups(["child"])[0].details.isEmpty, "a saved child needs its parent enabled")
        precondition(groups(["plain"])[0].details.isEmpty, "a switch with no details adds no section")

        let brightness = groups(["brightness"])[0].details
        precondition(brightness.map(\.id) == ["brightness"], "one enabled feature has sections")
        precondition(brightness[0].dependents.map(\.id) == ["child"] && brightness[0].hasRows
                     && brightness[0].hasOptions && brightness[0].hasCommands, "Options and Commands are independent")
        let nested = groups(["brightness", "child", "grandchild", "loopA", "loopB", "orphan", "missing"])[0].details
        precondition(nested.map(\.id) == ["brightness", "child", "grandchild"], "nested details in order")
        precondition(nested[1].dependents.map(\.id) == ["grandchild"] && !nested[1].hasRows
                     && nested[1].hasOptions && !nested[1].hasCommands, "dependent-only Options")
        precondition(nested[2].dependents.isEmpty && nested[2].hasOptions && !nested[2].hasCommands, "row-only Options")
        let sound = groups(["mic", "speaker"])[1].details
        precondition(sound.map(\.id) == ["speaker", "mic"], "a dependent with two parents appears only once")
        precondition(sound[0].dependents.map(\.id) == ["another"], "a dependent needs every parent enabled")
        precondition(!sound[1].hasOptions && sound[1].hasCommands, "Commands can stand alone")
        precondition(groups(["speaker"])[1].details.isEmpty, "one parent off hides a dependent")

        func downloadSwitches(_ enabled: Set<String>) -> [String] {
            groups(enabled, in: .downloads).flatMap { $0.switches.map(\.id) }
        }
        precondition(downloadSwitches(["bond"]) == ["download", "torrents"], "any-of hides a saved-on switch")
        precondition(downloadSwitches(["torrents"]) == ["download", "bond", "torrents"], "Torrents is enough")
        precondition(downloadSwitches(["download", "fast"]) == ["download", "bond", "torrents"],
                     "Fast Downloads is enough")
        precondition(!groups(["torrents"], in: .downloads)[0].details.contains { $0.id == bond.id },
                     "showing an off switch keeps its details hidden")
        precondition(groups(["torrents", "bond"], in: .downloads)[0].details.first?.id == bond.id,
                     "showing an enabled switch keeps its details visible")
        precondition(layout.listedOwners(of: grandchild) == ["brightness"], "search lands on the listed ancestor")
        precondition(layout.listedOwners(of: orphan).isEmpty && layout.listedOwners(of: loopA).isEmpty,
                     "invalid dependency chains get no search target")
        precondition(layout.listedOwners(of: bond) == ["download", "torrents"], "any-of search reaches both parents")
        print("PASSED")
    }
}
