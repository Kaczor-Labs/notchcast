// notchcast-sources: Tinycast/Features/Notchcast/Cleaner/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Cleaner/Service/CleanerScanner.swift
// notchcast-sources: Tinycast/Features/Notchcast/Cleaner/Service/CleanerBrowserVersions.swift
// notchcast-sources: Tinycast/Features/Notchcast/Cleaner/Service/CleanerUserAreas.swift
// notchcast-sources: Tinycast/Features/Notchcast/Cleaner/Service/CleanerRunner.swift
// notchcast-sources: Tinycast/Features/Notchcast/Cleaner/Service/CleanerRunningApps.swift
// notchcast-sources: Tinycast/Features/Uninstall/Model/*.swift
// notchcast-sources: Tests/nc-Cleaner-fixture.swift

import Foundation

@main
struct CleanerRunnerTest {
    static func main() async throws {
        try await checksEachItem()
        try await rejectsChangedRoot()
        try await checksWhatWentToTheTrash()
        try await rechecksMakersAndScripts()
    }

    private static func checksEachItem() async throws {
        let fs = CleanerTestFileSystem()
        let failed = CleanerTestFileSystem.item("a-failed")
        let changed = CleanerTestFileSystem.item("b-changed")
        let missing = CleanerTestFileSystem.item("c-missing")
        let inUse = CleanerTestFileSystem.item("d-running")
        let openFolder = CleanerTestFileSystem.item("e-open")
        let good = CleanerTestFileSystem.item("f-good")
        let child = changed.appending(component: "entry")
        let openFile = openFolder.appending(component: "entry")

        for folder in [changed, openFolder] { fs.put(folder, directory: true) }
        for file in [failed, child, missing, inUse, openFile, good] { fs.put(file, size: 64) }

        let plan = try await fs.scanner.scan(home: CleanerTestFileSystem.area.home, apps: .init())
        precondition(plan.defaultSelection.checked == [failed, changed, missing, inUse, openFolder, good])
        fs.put(child, size: 64)
        fs.remove(missing)
        fs.failTrash(of: failed)
        try fs.holdOpen(openFile)
        let runner = CleanerRunner(scanner: fs.scanner, runningApps: { .init(running: ["drunning"]) })
        let report = await runner.run(plan, selection: plan.defaultSelection)
        precondition(report.entries.map(\.outcome) == [
            .failed(.fileWriteNoPermission), .skipped(.changed), .skipped(.missing), .skipped(.heldBack(.runningApp)),
            .skipped(.heldBack(.openFile)), .trashed(MeasuredSize(bytes: 64))
        ])
        precondition(report.movedCount == 1 && report.knownMovedBytes == 64)
        precondition(fs.trashCalls == [failed, good])
        _ = try fs.inspect(CleanerTestFileSystem.area.root)
    }

    private static func rejectsChangedRoot() async throws {
        let fs = CleanerTestFileSystem()
        let item = CleanerTestFileSystem.item("example")
        fs.put(item, size: 100)
        let area = CleanerTestFileSystem.area
        let plan = try await fs.scanner.scan(home: area.home, apps: .init())
        let runner = CleanerRunner(scanner: fs.scanner, runningApps: { .init() })

        fs.put(area.root, link: true)
        let report = await runner.run(plan, selection: plan.defaultSelection)
        precondition(report.entries == [.init(id: item, outcome: .skipped(.heldBack(.unsafePath)))])
        precondition(fs.trashCalls.isEmpty)
    }

    private static func checksWhatWentToTheTrash() async throws {
        let fs = CleanerTestFileSystem()
        let swapped = CleanerTestFileSystem.item("a-swapped")
        let tool = CleanerTestFileSystem.item("b-tool")
        let program = tool.appending(component: "bin")
        let good = CleanerTestFileSystem.item("c-good")
        fs.put(tool, directory: true)
        for file in [swapped, program, good] { fs.put(file, size: 32) }
        let plan = try await fs.scanner.scan(home: CleanerTestFileSystem.area.home, apps: .init())
        precondition(plan.defaultSelection.checked == [swapped, tool, good])

        fs.swapDuringTrash(of: swapped)
        try fs.run(program)
        let runner = CleanerRunner(scanner: fs.scanner, runningApps: { .init() })
        let report = await runner.run(plan, selection: plan.defaultSelection)
        precondition(report.entries.map(\.outcome) == [
            .trashedUnverified, .skipped(.heldBack(.runningProgram)), .trashed(MeasuredSize(bytes: 32))
        ])
        precondition(report.movedCount == 1 && report.knownMovedBytes == 32)
        precondition(fs.trashCalls == [swapped, good])
        _ = try fs.inspect(CleanerTestFileSystem.trash.appending(component: "c-good"))
    }

    private static func rechecksMakersAndScripts() async throws {
        let fs = CleanerTestFileSystem()
        let maker = CleanerTestFileSystem.item("jetbrains.com")
        let scripted = CleanerTestFileSystem.item("tool")
        for folder in [maker, scripted] { fs.put(folder, directory: true) }
        fs.put(maker.appending(component: "idea.log"), size: 16)
        fs.put(scripted.appending(component: "worker.js"), size: 16)
        let plan = try await fs.scanner.scan(home: CleanerTestFileSystem.area.home, apps: .init())
        precondition(plan.defaultSelection.checked == [maker, scripted])

        fs.runScript(named: scripted.path + "/worker.js")
        let names = Set(CleanerPolicy.makerNames(of: "com.jetbrains.intellij").map(CleanerPolicy.appKey))
        let runner = CleanerRunner(scanner: fs.scanner, runningApps: { .init(running: names) })
        let report = await runner.run(plan, selection: plan.defaultSelection)
        precondition(report.entries.map(\.outcome) == [
            .skipped(.heldBack(.runningApp)), .skipped(.heldBack(.runningProgram))
        ])
        precondition(fs.trashCalls.isEmpty)
    }
}
