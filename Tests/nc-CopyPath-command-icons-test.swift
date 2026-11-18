// notchcast-kit: notchcast-command-icons
// notchcast-sources: Tinycast/Features/Notchcast/CopyPath/CopyPathAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/CopyPath/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/CopyPath/Service/CopyPathModule.swift
// notchcast-reads: Tinycast/Features/Notchcast/NotchcastCore.swift
@main
@MainActor
enum CopyPathCommandIconTests {
    static func main() { NotchcastCommandIconCheck.run(CopyPathAddon.self) }
}

// The shipped `live` system is left out: this stands in so the descriptor compiles.
extension CopyPathSystem {
    static var live: Self { fatalError("the harness never makes a module") }
}
