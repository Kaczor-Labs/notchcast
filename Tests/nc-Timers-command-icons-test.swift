// notchcast-kit: notchcast-command-icons
// notchcast-sources: Tinycast/Features/Notchcast/Timers/TimersAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/Timers/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Timers/Service/*.swift
// notchcast-reads: Tinycast/Features/Notchcast/NotchcastCore.swift
@main
@MainActor
enum TimersCommandIconTests {
    static func main() { NotchcastCommandIconCheck.run(TimersAddon.self) }
}
