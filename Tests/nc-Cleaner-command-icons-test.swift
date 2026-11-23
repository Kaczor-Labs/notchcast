// notchcast-kit: notchcast-command-icons
// notchcast-sources: Tinycast/Features/Notchcast/Cleaner/CleanerAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/Cleaner/CleanerModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Cleaner/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Cleaner/Service/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Cleaner/Settings/*.swift
// notchcast-sources: Tinycast/Features/Uninstall/Model/*.swift
// notchcast-sources: Tinycast/Platform/Permissions.swift Tinycast/Platform/CalendarAccess.swift
// notchcast-sources: Tinycast/Platform/CameraAccess.swift
// notchcast-reads: Tinycast/Features/Notchcast/NotchcastCore.swift
@main
@MainActor
enum CleanerCommandIconTests {
    static func main() { NotchcastCommandIconCheck.run(CleanerAddon.self) }
}

// The shipped palette and Trash wiring are left out: these stand in so the descriptor compiles.
extension CleanerModule {
    static func live(_ context: NotchcastContext) -> CleanerModule { fatalError("the harness never makes a module") }
    func openScreen() {}
}
