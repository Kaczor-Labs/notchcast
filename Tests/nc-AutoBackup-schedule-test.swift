// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Notchcast/AutoBackup/AutoBackupAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/AutoBackup/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/AutoBackup/Service/*.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift Tests/NotchcastTapFixtures.swift

import Foundation
import SwiftUI

// The settings view is left out: the module runs against a fake backup in a scratch folder.
struct AutoBackupSettingsView: View {
    init(context: NotchcastContext) {}
    var body: some View { EmptyView() }
}

typealias Schedule = AutoBackupSchedule

let utc = TimeZone(identifier: "UTC")!
let start = Date(timeIntervalSince1970: 1_800_000_000)

func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

/// The folder as the schedule sees it: a set of paths, never the disk.
final class FakeDisk {
    var files: Set<String> = []
    func exists(_ path: String) -> Bool { files.contains(path) }
}

@MainActor
final class FakeBackup: NotchcastSettingsBackup {
    var settings = Data("a".utf8)
    var fails = false
    var writes: [URL] = []
    var observers: [@MainActor @Sendable () -> Void] = []

    struct DiskFull: Error {}

    func currentSettings() -> Data? { settings }
    func observeSettings(_ onChange: @escaping @MainActor @Sendable () -> Void) { observers.append(onChange) }

    func write(_ settings: Data, to file: URL) async throws {
        if fails { throw DiskFull() }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try settings.write(to: file, options: .atomic)
        writes.append(file)
    }

    func restore(_ file: URL) async {}

    /// What the stock bridge does when a read value changes.
    func change(to text: String) {
        settings = Data(text.utf8)
        let pending = observers
        observers = []
        pending.forEach { $0() }
    }
}

@MainActor
final class Clock {
    var now = start
}

@MainActor
final class Rig {
    let suite = "nc-AutoBackup-test.\(UUID())"
    let defaults: UserDefaults
    let folder = FileManager.default.temporaryDirectory
        .appending(path: "nc-AutoBackup-test.\(UUID())", directoryHint: .isDirectory)
    let presenter = RecordingPresenter()
    let backup = FakeBackup()
    let clock = Clock()
    let controller: NotchcastController

    init() {
        defaults = UserDefaults(suiteName: suite)!
        let hub = NotchcastTapHub(syntheticTag: 0x54494E59, isTrusted: { true }, makeSession: { FakeSession($0) })
        let clock = clock
        controller = NotchcastController(
            addons: [AutoBackupAddon.self], defaults: defaults, hub: hub, dictation: FakeDictation(),
            presenter: presenter, now: { clock.now }, settingsBackup: backup)
        AutoBackupPreferences(defaults: defaults).chosenFolder = folder.path(percentEncoded: false)
        controller.start()
    }

    var preferences: AutoBackupPreferences { AutoBackupPreferences(defaults: defaults) }
    var onDisk: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []).sorted()
    }

    func set(_ on: Bool) async {
        controller.preferences.set(AutoBackupPreferences.switchID, on: on)
        await settle()
    }

    /// Restarts the module after `seconds`, so its timer starts from a due time already passed.
    func reopen(after seconds: TimeInterval) async {
        await set(false)
        clock.now = clock.now.addingTimeInterval(seconds)
        await set(true)
    }

    func finish() {
        controller.stop()
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: folder)
    }
}

/// Main-actor turns only: every timer here is already due, so nothing waits on the clock.
func settle() async {
    for _ in 0..<50 { await Task.yield() }
}

@main
enum AutoBackupScheduleTests {
    @MainActor
    static func main() async {
        debounceAndGap()
        changeDetection()
        rotation()
        failures()
        names()
        await module()
        print("PASS: auto-backup schedule, rotation and module checks; no real clock or home folder")
    }

    static func debounceAndGap() {
        var s = Schedule()
        precondition(s.due() <= start, "a first run is due at once")
        precondition(s.tick(at: start, digest: "a", timeZone: utc, exists: { _ in false }) != nil, "first tick acts")
        _ = s.didWrite("/b/1", digest: "a", at: start, keep: 10, exists: { _ in true })
        precondition(s.due() == at(Schedule.checkInterval), "without a change the next check is a day later")
        s.noteChange(at: at(60))
        precondition(s.due() == at(Schedule.minimumGap), "a change waits out the 10-minute gap since the last write")
        precondition(s.tick(at: at(599), digest: "b", timeZone: utc, exists: { _ in true }) == nil, "not before")
        s.noteChange(at: at(590))
        precondition(s.due() == at(620), "a later change restarts the 30 s debounce past the gap")
        precondition(s.tick(at: at(620), digest: "b", timeZone: utc, exists: { _ in true }) != nil, "due acts")
        precondition(s.pendingChange == nil && s.lastCheck == at(620), "a tick consumes the change")
        precondition(s.due() == at(620 + Schedule.checkInterval), "then the daily check")
    }

    static func changeDetection() {
        let disk = FakeDisk()
        var s = Schedule()
        _ = s.tick(at: start, digest: "a", timeZone: utc, exists: disk.exists)
        disk.files.insert("/b/1")
        _ = s.didWrite("/b/1", digest: "a", at: start, keep: 10, exists: disk.exists)
        let day = at(Schedule.checkInterval)
        precondition(s.tick(at: day, digest: "a", timeZone: utc, exists: disk.exists) == .skip, "unchanged skips")
        precondition(s.lastWrite == start, "a skip writes nothing")
        let later = at(2 * Schedule.checkInterval)
        disk.files.remove("/b/1")
        if case .write = s.tick(at: later, digest: "a", timeZone: utc, exists: disk.exists) {} else {
            preconditionFailure("unchanged but the last backup is gone: write again")
        }
        s.noteChange(at: later)
        let changed = at(3 * Schedule.checkInterval)
        if case .write = s.tick(at: changed, digest: "b", timeZone: utc, exists: { _ in true }) {} else {
            preconditionFailure("changed settings write")
        }
    }

    static func rotation() {
        let disk = FakeDisk()
        disk.files = ["/b/someone-else.tinycast"]
        var s = Schedule()
        var removed: [String] = []
        for index in 1...11 {
            let path = "/b/\(index)"
            disk.files.insert(path)
            removed += s.didWrite(path, digest: "\(index)", at: at(Double(index) * 700), keep: 10, exists: disk.exists)
            removed.forEach { disk.files.remove($0) }
        }
        precondition(removed == ["/b/1"], "the 11th backup removes only the oldest")
        precondition(s.written.count == 10 && s.written.first == "/b/2", "ten stay, oldest first")
        precondition(disk.files.contains("/b/someone-else.tinycast"), "a file Notchcast did not write is never removed")
        disk.files.remove("/b/5")
        let trimmed = s.didWrite("/b/12", digest: "12", at: at(9_000), keep: 3, exists: disk.exists)
        precondition(trimmed == ["/b/2", "/b/3", "/b/4", "/b/6", "/b/7", "/b/8", "/b/9"],
                     "a lower keep trims, gone files skipped")
        precondition(s.written == ["/b/10", "/b/11", "/b/12"], "the newest three stay")
        precondition(s.didWrite("/b/12", digest: "12", at: at(9_100), keep: 0, exists: { _ in true }) == ["/b/10", "/b/11"],
                     "keep never drops below one, and a rewritten name counts once")
    }

    static func failures() {
        var s = Schedule()
        precondition(s.didFail(), "the first failure reports")
        precondition(!s.didFail(), "a second failure in a row stays quiet")
        _ = s.didWrite("/b/1", digest: "a", at: start, keep: 10, exists: { _ in true })
        precondition(s.didFail(), "after a success, the next failure reports again")
    }

    static func names() {
        let name = Schedule.fileName(at: Date(timeIntervalSince1970: 1_800_000_005), timeZone: utc)
        precondition(name == "Notchcast Settings 2027-01-15 08.00.05.tinycast", "name: \(name)")
        let warsaw = Schedule.fileName(
            at: Date(timeIntervalSince1970: 1_800_000_005), timeZone: TimeZone(identifier: "Europe/Warsaw")!)
        precondition(warsaw == "Notchcast Settings 2027-01-15 09.00.05.tinycast", "local time: \(warsaw)")
        let documents = URL(filePath: "/fake/Documents", directoryHint: .isDirectory)
        precondition(Schedule.folder(chosen: nil, documents: documents, channel: nil).path(percentEncoded: false)
            == "/fake/Documents/Notchcast Backups/", "the default folder")
        precondition(Schedule.folder(chosen: nil, documents: documents, channel: "app.notchcast.dev").path(percentEncoded: false)
            == "/fake/Documents/Notchcast Backups/app.notchcast.dev/", "a Debug channel gets its own subfolder")
        precondition(Schedule.folder(chosen: "/x/y", documents: documents, channel: "dev").path(percentEncoded: false)
            == "/x/y/dev/", "a chosen folder keeps the channel subfolder")
        let saved = Schedule(written: ["/b/1"], lastDigest: "a", lastWrite: start)
        let json = try? JSONEncoder().encode(saved)
        precondition(json.flatMap { try? JSONDecoder().decode(Schedule.self, from: $0) } == saved, "state round trips")
    }

    @MainActor
    static func module() async {
        let rig = Rig()
        defer { rig.finish() }
        precondition(rig.backup.writes.isEmpty, "off by default: nothing written")
        await rig.set(true)
        precondition(rig.backup.writes.count == 1, "turning it on writes the first backup")
        precondition(rig.onDisk.count == 1 && rig.onDisk[0].hasPrefix("Notchcast Settings "), "one file in the chosen folder")
        await rig.reopen(after: Schedule.checkInterval)
        precondition(rig.backup.writes.count == 1, "the daily check skips unchanged settings")

        rig.backup.change(to: "b")
        await settle()
        precondition(rig.preferences.schedule.pendingChange == rig.clock.now, "a change is noted")
        await rig.reopen(after: Schedule.minimumGap)
        precondition(rig.backup.writes.count == 2, "a change writes once the gap has passed")

        rig.preferences.keep = 2
        rig.backup.change(to: "c")
        await rig.reopen(after: Schedule.minimumGap)
        precondition(rig.backup.writes.count == 3 && rig.onDisk.count == 2, "keep 2: the oldest file is deleted")
        precondition(!FileManager.default.fileExists(atPath: rig.backup.writes[0].path(percentEncoded: false)),
                     "the oldest backup went")

        rig.backup.fails = true
        rig.backup.change(to: "d")
        await rig.reopen(after: Schedule.minimumGap)
        rig.backup.change(to: "e")
        await rig.reopen(after: Schedule.minimumGap)
        let notices = rig.presenter.log.filter { $0.hasPrefix("post autoBackupSettings.failed") }
        precondition(notices.count == 1, "two failures in a row show one notice: \(rig.presenter.log)")
        rig.backup.fails = false
        await rig.reopen(after: Schedule.checkInterval)
        precondition(rig.backup.writes.count == 4, "the next trigger retries and writes")
        precondition(rig.onDisk.count == 2, "rotation still holds")
    }
}
