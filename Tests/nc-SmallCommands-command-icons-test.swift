// notchcast-kit: notchcast-command-icons
// notchcast-sources: Tinycast/Features/Notchcast/SmallCommands/SmallCommandsAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/SmallCommands/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/SmallCommands/Service/SmallCommandsModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/SmallCommands/Service/SmallCommandsSystem.swift
// notchcast-sources: Tinycast/Features/Notchcast/SmallCommands/Service/AirDropService.swift
// notchcast-sources: Tinycast/Features/Notchcast/SmallCommands/Service/ShortenLinkSession.swift
// notchcast-reads: Tinycast/Features/Notchcast/NotchcastCore.swift
@main
@MainActor
enum SmallCommandsCommandIconTests {
    static func main() { NotchcastCommandIconCheck.run(SmallCommandsAddon.self) }
}

// The shipped `live` system is left out: this stands in so the descriptor compiles.
extension SmallCommandsSystem {
    static var live: Self { fatalError("the harness never makes a module") }
}
