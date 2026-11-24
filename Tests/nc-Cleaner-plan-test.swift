// notchcast-sources: Tinycast/Features/Notchcast/Cleaner/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Cleaner/Service/CleanerScanner.swift
// notchcast-sources: Tinycast/Features/Notchcast/Cleaner/Service/CleanerBrowserVersions.swift
// notchcast-sources: Tinycast/Features/Notchcast/Cleaner/Service/CleanerUserAreas.swift
// notchcast-sources: Tinycast/Features/Notchcast/Cleaner/Service/CleanerRunningApps.swift
// notchcast-sources: Tinycast/Features/Uninstall/Model/*.swift
// notchcast-sources: Tests/nc-Cleaner-fixture.swift

import Foundation
import Synchronization

@main
@MainActor
struct CleanerPlanTest {
    static func main() async throws {
        try await checksSelection()
        try await givesEachRowItsOwnBudget()
    }

    private static func checksSelection() async throws {
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
        let plan = try await fs.scanner.scan(home: CleanerTestFileSystem.area.home, apps: apps) { streamed.append($0) }
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
        var selection = CleanerSelection(plan: plan, checked: Set(rows.keys).union([CleanerTestFileSystem.area.root]))
        selection.set(locked, checked: true, in: plan)
        selection.set(running, checked: true, in: plan)
        precondition(selection.checked == [safe])
        precondition(fs.trashCalls.isEmpty)
    }

    private static func givesEachRowItsOwnBudget() async throws {
        let large = CleanerTestFileSystem.item("a-large")
        let slow = CleanerTestFileSystem.item("b-slow")
        let small = CleanerTestFileSystem.item("c-small")
        let now = Mutex(ContinuousClock.now)
        let fs = CleanerTestFileSystem { url in
            if url == slow { now.withLock { $0 = $0.advanced(by: .seconds(3)) } }
        }
        fs.put(large, directory: true)
        for index in 0..<19_999 {
            fs.put(large.appending(component: "\(index)"))
        }
        fs.put(slow, directory: true)
        fs.put(slow.appending(component: "entry"))
        fs.put(small, size: 64)

        var scanner = fs.scanner
        scanner.monotonic = { now.withLock { $0 } }
        let plan = try await scanner.scan(home: CleanerTestFileSystem.area.home, apps: .init())
        precondition(plan.items.map(\.standing) == [.recommended, .locked(.scanLimit), .recommended])
        precondition(plan.items.last?.size?.bytes == 64)
        precondition(plan.defaultSelection.checked == [large, small])
    }
}
