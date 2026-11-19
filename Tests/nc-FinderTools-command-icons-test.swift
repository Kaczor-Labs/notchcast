// notchcast-kit: notchcast-command-icons
// notchcast-sources: Tinycast/Features/Notchcast/FinderTools/FinderToolsAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/FinderTools/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/FinderTools/Service/FinderToolsModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/FinderTools/Service/FinderToolsSystem.swift
// notchcast-reads: Tinycast/Features/Notchcast/NotchcastCore.swift
@main
@MainActor
enum FinderToolsCommandIconTests {
    static func main() { NotchcastCommandIconCheck.run(FinderToolsAddon.self) }
}

// The shipped `live` system is left out: this stands in so the descriptor compiles.
extension FinderToolsSystem {
    static var live: Self { fatalError("the harness never makes a module") }
}
