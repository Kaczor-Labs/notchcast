// notchcast-sources: Tinycast/Features/Notchcast/Cleaner/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Cleaner/Service/*.swift
// notchcast-sources: Tinycast/Features/Uninstall/Model/*.swift
// notchcast-sources: Tinycast/Platform/Permissions.swift
// notchcast-sources: Tinycast/Platform/CalendarAccess.swift Tinycast/Platform/CameraAccess.swift
// notchcast-sources: Tests/nc-Cleaner-fixture.swift

@main
@MainActor
struct CleanerSessionTest {
    static func main() async throws {
        let fs = CleanerTestFileSystem()
        let item = CleanerTestFileSystem.item("org.example.cache")
        fs.put(item, size: 64)
        var hasAccess = false
        let session = CleanerSession(
            area: CleanerTestFileSystem.area, runner: CleanerRunner(scanner: fs.scanner, runningApps: { .init() }),
            hasAccess: { hasAccess })

        await session.open()
        precondition(session.phase == .needsAccess && fs.reads == 0)
        hasAccess = true
        await session.open()
        precondition(session.phase == .review && session.selection?.checked == [item])

        await session.clean { selection in
            precondition(selection.checked == [item])
            return false
        }
        precondition(session.phase == .review && fs.trashCalls.isEmpty)

        hasAccess = false
        await session.clean { _ in true }
        precondition(session.phase == .needsAccess && fs.trashCalls.isEmpty)

        hasAccess = true
        await session.open()
        await session.clean { _ in true }
        precondition(session.phase == .done && session.report?.knownMovedBytes == 64)
        precondition(fs.trashCalls == [item])
    }
}
