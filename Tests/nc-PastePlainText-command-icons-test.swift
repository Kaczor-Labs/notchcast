// notchcast-kit: notchcast-command-icons
// notchcast-sources: Tinycast/Features/Notchcast/PastePlainText/PastePlainTextAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/PastePlainText/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/PastePlainText/Service/PastePlainTextModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/PastePlainText/Service/PastePlainTextSystem.swift
// notchcast-reads: Tinycast/Features/Notchcast/NotchcastCore.swift
@main
@MainActor
enum PastePlainTextCommandIconTests {
    static func main() { NotchcastCommandIconCheck.run(PastePlainTextAddon.self) }
}

// The shipped `live` system is left out: this stands in so the descriptor compiles.
extension PastePlainTextSystem {
    static var live: Self { fatalError("the harness never makes a module") }
}
