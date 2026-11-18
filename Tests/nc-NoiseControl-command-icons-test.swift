// notchcast-kit: notchcast-command-icons
// notchcast-sources: Tinycast/Features/Notchcast/NoiseControl/NoiseControlAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/NoiseControl/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/NoiseControl/Service/NoiseControlModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/NoiseControl/Service/NoiseControlSystem.swift
// notchcast-sources: Tinycast/Features/Notchcast/NoiseControl/Service/NoiseControlSwitcher.swift
// notchcast-reads: Tinycast/Features/Notchcast/NotchcastCore.swift
@main
@MainActor
enum NoiseControlCommandIconTests {
    static func main() { NotchcastCommandIconCheck.run(NoiseControlAddon.self) }
}

// The shipped `live` system is left out: this stands in so the descriptor compiles.
extension NoiseControlSystem {
    static var live: Self { fatalError("the harness never makes a module") }
}
