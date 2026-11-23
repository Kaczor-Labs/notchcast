// notchcast-sources: Tinycast/Features/Notchcast/Cleaner/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Cleaner/Service/CleanerScanner.swift
// notchcast-sources: Tinycast/Features/Notchcast/Cleaner/Service/CleanerRunningApps.swift
// notchcast-sources: Tinycast/Features/Uninstall/Model/*.swift
// notchcast-sources: Tests/nc-Cleaner-fixture.swift

import Foundation

@main
@MainActor
struct CleanerPlanTest {
    static func main() async throws {
        let fs = CleanerTestFileSystem()
        let safe = CleanerTestFileSystem.item("com.example.atlas #1")
        let recent = CleanerTestFileSystem.item("com.example.recent")
        let running = CleanerTestFileSystem.item("Example Painter")
        let locked = CleanerTestFileSystem.item("com.example.locked")
        let privateWork = CleanerTestFileSystem.item("com.example.editor")
        let link = CleanerTestFileSystem.item("com.example.link")
        fs.put(safe, directory: true)
        fs.put(safe.appending(component: "tile"), size: 48)
        fs.put(recent, directory: true)
        fs.put(recent.appending(component: "tile"), size: 32, modified: 9_101)
        fs.put(running, size: 16)
        fs.put(locked, locked: true)
        fs.put(privateWork, directory: true)
        fs.put(privateWork.appending(component: "LocalHistory"), directory: true)
        fs.put(link, link: true)
        for name in ["com.apple.test", "ABCDEF1234.group.com.apple.test", "CloudKit", "AudioComponentRegistrar",
                     ".DS_Store", "com.example.cleaner"] {
            fs.put(CleanerTestFileSystem.item(name))
        }

        var streamed: [CleanerItem] = []
        let apps = CleanerRunningApps(running: ["examplepainter"], own: ["comexamplecleaner"])
        let plan = try await fs.scanner.scan(CleanerTestFileSystem.area, apps: apps) { streamed.append($0) }
        let rows = Dictionary(uniqueKeysWithValues: plan.items.map { ($0.id, $0) })
        precondition(streamed == plan.items)
        precondition(Set(rows.keys) == [safe, recent, running, locked, privateWork, link])
        precondition(rows[safe]?.standing == .recommended && rows[safe]?.size?.bytes == 48)
        precondition(rows[recent]?.standing == .heldBack(.recentWrite) && rows[recent]?.size?.bytes == 32)
        precondition(rows[running]?.standing == .heldBack(.runningApp) && rows[running]?.size?.bytes == 16)
        precondition(rows[locked]?.standing == .locked(.locked(.userLocked)))
        precondition(rows[privateWork]?.standing == .locked(.protectedData))
        precondition(rows[link]?.standing == .locked(.unsafePath))
        precondition(plan.knownBytes == 96 && plan.unknownCount == 3)
        precondition(plan.defaultSelection.checked == [safe])
        var selection = CleanerSelection(plan: plan, checked: Set(rows.keys).union([plan.area.root]))
        selection.set(locked, checked: true, in: plan)
        selection.set(running, checked: true, in: plan)
        precondition(selection.checked == [safe])
        precondition(fs.trashCalls.isEmpty)
    }
}
