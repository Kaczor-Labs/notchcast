// notchcast-kit: notchcast-command-icons
// notchcast-sources: Tinycast/Features/Notchcast/Threads/ThreadsAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/Threads/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Threads/Service/*.swift
// notchcast-reads: Tinycast/Features/Notchcast/NotchcastCore.swift
import SwiftUI

@main
@MainActor
enum ThreadsCommandIconTests {
    static func main() { NotchcastCommandIconCheck.run(ThreadsAddon.self) }
}

// The shipped settings view is left out: this stands in so the descriptor compiles.
struct ThreadsSettingsView: View {
    init(context: NotchcastContext) {}
    var body: some View { EmptyView() }
}
