// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift Tinycast/Platform/ProcessExit.swift
// notchcast-sources: Tinycast/Platform/ExecutableLocator.swift
// notchcast-sources: Tinycast/Features/Notchcast/Archives/ArchivesAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/Archives/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Archives/Service/ArchivesModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Archives/Service/ArchivesEnvironment.swift
// notchcast-sources: Tinycast/Features/Notchcast/Archives/Service/ArchiveExtractor.swift
// notchcast-sources: Tinycast/Features/Notchcast/Archives/Service/ArchiveCompressor.swift
// notchcast-sources: Tinycast/Features/Notchcast/Archives/Service/ArchiveProcess.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift

import AppKit
import Synchronization
import SwiftUI

// The shipped `live` and settings UI are left out: these stand in, so `makeModule` runs as shipped.

struct ArchivesSettingsView: View {
    init(context: NotchcastContext) {}
    var body: some View { EmptyView() }
}

@MainActor var harnessEnvironment: ArchivesEnvironment?

extension ArchivesEnvironment {
    static func live() -> Self { harnessEnvironment! }
}

func check(_ condition: Bool, _ message: @autoclosure () -> String) {
    if !condition { fatalError(message()) }
}

/// Every password the harness types carries this, so a leak anywhere is one `contains` away.
let marker = "7Qx"
let (right, wrong) = ("nc-right-7Qx", "nc-wrong-7Qx")
let variable = "HATCHZIP_PASSWORD"
let twoFiles = """
          Size  Name
           1 B  a.txt
           1 B  b/c.txt
    2 entries, 2 B uncompressed, 7 B zip archive
    """

/// Plays HatchZip as probed: exit 5 until the variable holds the password, progress kept in a side
/// file naming its output folder, and `restore` refused for an archive with encrypted names.
final class FakeTools: Sendable {
    struct Call {
        var tool: String
        var arguments: [String]
        var environment: [String: String]
    }

    struct State {
        var calls: [Call] = []
        var passwords: [String: String] = [:]
        var hiddenNames: Set<String> = []
        var extractStatuses: [Int32] = []
        var hold: Set<String> = []
        var held: CheckedContinuation<Void, Never>?
        var heldStarted = false
        var journalInPlaceAtExtract: [Bool] = []
        var journalLeaks = 0
    }

    let state = Mutex(State())
    let journal: URL

    init(journal: URL) { self.journal = journal }

    func locate(_ name: String) -> URL? { URL(filePath: "/fake/bin/\(name)") }

    func run(_ tool: URL, _ arguments: [String], _ environment: [String: String]) async throws -> ArchiveProcessResult {
        try Task.checkCancellation()
        let name = tool.lastPathComponent
        let journalled = (try? Data(contentsOf: journal)) ?? Data()
        state.withLock {
            $0.calls.append(Call(tool: name, arguments: arguments, environment: environment))
            if journalled.range(of: Data(marker.utf8)) != nil { $0.journalLeaks += 1 }
        }
        let archive = URL(filePath: arguments[1])
        if name == "bsdtar" {
            guard arguments[0] == "-tvf" else { return try extract(into: URL(filePath: arguments.last!)) }
            return ArchiveProcessResult(status: 0, output: "-rw-r--r--  0 me  staff  1 Jan  1 12:00 a.txt\n")
        }
        let side = archive.path + ".hatchzip"
        let password = state.withLock { $0.passwords[archive.lastPathComponent] }
        if let password, ["list", "extract", "check"].contains(arguments[0]), environment[variable] != password {
            return ArchiveProcessResult(status: 5, errors: "Incorrect password.\nerror: incorrect password\n")
        }
        switch arguments[0] {
        case "list": return ArchiveProcessResult(status: 0, output: twoFiles)
        case "check": return ArchiveProcessResult(status: 0, output: "required 29.9 MB")
        case "restore":
            guard FileManager.default.fileExists(atPath: side) else { return ArchiveProcessResult(status: 1) }
            if state.withLock({ $0.hiddenNames.contains(archive.lastPathComponent) }) {
                return ArchiveProcessResult(status: 1, errors: "error: has encrypted file names")
            }
            try FileManager.default.removeItem(atPath: side)
            return ArchiveProcessResult(status: 0)
        default: break
        }
        let output = URL(filePath: arguments[arguments.firstIndex(of: "-o")! + 1])
        if let started = try? String(contentsOfFile: side, encoding: .utf8), started != output.path {
            return ArchiveProcessResult(
                status: 1, errors: "error: this archive is already partially extracted to \(started). Complete it first")
        }
        let jobs = ArchiveJob.decode(journalled)
        state.withLock { $0.journalInPlaceAtExtract.append(jobs.first { $0.archive == archive }?.inPlace ?? false) }
        if state.withLock({ $0.hold.contains(archive.lastPathComponent) }) {
            try output.path.write(toFile: side, atomically: true, encoding: .utf8)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try Data("half".utf8).write(to: output.appending(path: "a.txt"))
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    state.withLock {
                        $0.heldStarted = true
                        $0.held = continuation
                    }
                }
            } onCancel: {
                state.withLock { $0.held?.resume() }
            }
            throw CancellationError()
        }
        let status = state.withLock { $0.extractStatuses.isEmpty ? 0 : $0.extractStatuses.removeFirst() }
        guard status == 0 else { return ArchiveProcessResult(status: status, errors: "error: no room") }
        try? FileManager.default.removeItem(atPath: side)
        return try extract(into: output)
    }

    private func extract(into output: URL) throws -> ArchiveProcessResult {
        for file in ["a.txt", "b/c.txt"] {
            let url = output.appending(path: file)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url)
        }
        return ArchiveProcessResult(status: 0)
    }
}

@MainActor
final class FakePresenter: IslandPresenting {
    var posts: [IslandNotice] = []
    var texts: [String] { posts.map(\.text) }
    var failures: [String] { posts.filter(\.isFailure).map(\.text) }

    func showLevel(_ level: IslandLevel) {}
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) { posts.append(notice) }
    func end(notice id: String) {}
    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {}
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
}

/// The password dialog as the core hook answers it: one queued answer per question, nil for Cancel.
@MainActor
final class Record {
    struct Ask: Equatable {
        var title: String
        var message: String?
        var field: String
        var confirm: String
    }

    var asks: [Ask] = []
    var answers: [String?] = []
    var besideAtAsk: [[String]] = []
    var holdAsk = false
    var heldAsk: CheckedContinuation<Void, Never>?
    var confirms: [String] = []
    var inPlaceAnswer = true
}

@MainActor
final class Rig {
    let suite = "nc-Archives-password-test.\(UUID())"
    let defaults: UserDefaults
    let folder: URL
    let presenter = FakePresenter()
    let tools: FakeTools
    let record = Record()
    let controller: NotchcastController

    init(
        folder existing: URL? = nil, hook: Bool = true, answers: [String?] = [], journal: [ArchiveJob] = [],
        passwords: [String: String] = [:], hiddenNames: Set<String> = []
    ) throws {
        folder = existing ?? FileManager.default.temporaryDirectory.appending(
            path: "nc-archives-pw-\(UUID())", directoryHint: .isDirectory)
        defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: "archives")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let journalURL = folder.appending(path: "support/archives.json")
        tools = FakeTools(journal: journalURL)
        tools.state.withLock {
            $0.passwords = passwords
            $0.hiddenNames = hiddenNames
        }
        if !journal.isEmpty {
            try FileManager.default.createDirectory(
                at: journalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try ArchiveJob.encode(journal).write(to: journalURL)
        }
        let (tools, record, folder) = (tools, record, folder)
        record.answers = answers
        harnessEnvironment = ArchivesEnvironment(
            journal: journalURL,
            extractor: ArchiveExtractor(locate: { tools.locate($0) }, run: { try await tools.run($0, $1, $2) }),
            compressor: ArchiveCompressor(locate: { _ in nil }, run: { _, _ in ArchiveProcessResult(status: 1) }),
            finderSelection: { [] }, setDefaultApp: { _ in }, reveal: { _ in }, pickArchives: { [] })
        let hub = NotchcastTapHub(
            syntheticTag: 0x54494E59, isTrusted: { true }, makeSession: { _ in fatalError("Archives installs no tap") })
        controller = NotchcastController(
            addons: [ArchivesAddon.self], defaults: defaults, hub: hub, dictation: FakeDictation(), presenter: presenter)
        let context = controller.context(forSwitch: "archives")!
        context.confirm = { title, _, _ in
            record.confirms.append(title)
            return record.inPlaceAnswer
        }
        if hook {
            context.askSecret = { title, message, field, confirm in
                record.asks.append(Record.Ask(title: title, message: message, field: field, confirm: confirm))
                record.besideAtAsk.append(
                    ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0 != "support" }
                        .sorted())
                if record.holdAsk { await withCheckedContinuation { record.heldAsk = $0 } }
                return record.answers.isEmpty ? nil : record.answers.removeFirst()
            }
        }
        controller.start()
    }

    var module: ArchivesModule? { controller.context(forSwitch: "archives")?.module(ArchivesModule.self) }
    var calls: [FakeTools.Call] { tools.state.withLock { $0.calls } }
    var steps: [String] { calls.map { $0.arguments[0] } }

    @discardableResult
    func archive(_ name: String) -> URL {
        let url = folder.appending(path: name)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: Data("archive \(name)".utf8))
        }
        return url
    }

    func exists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: folder.appending(path: name).path) }
    func bytes(_ name: String) -> Data? { try? Data(contentsOf: archive(name)) }

    var visible: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0 != "support" }.sorted()
    }

    var staging: [String] { visible.filter { $0.hasPrefix(".notchcast-extract-") } }

    func journal() -> [ArchiveJob] {
        ArchiveJob.decode((try? Data(contentsOf: harnessEnvironment!.journal)) ?? Data())
    }

    func extract(_ names: String...) async {
        module!.open(names.map { archive($0) })
        await module!.drain()
    }

    /// Acceptance 2, after every case: the password never reaches an argument, the journal, a notice,
    /// or any program but HatchZip's list, extract and check.
    func audit() {
        for call in calls {
            check(!call.arguments.contains { $0.contains(marker) }, "a password reached arguments: \(call.arguments)")
            check(call.environment.keys.allSatisfy { $0 == variable }, "only the variable is added: \(call.environment)")
            if call.environment[variable] != nil {
                check(call.tool == "hatchzip" && ["list", "extract", "check"].contains(call.arguments[0]),
                      "only HatchZip's list, extract and check get it: \(call.tool) \(call.arguments)")
            }
        }
        check(tools.state.withLock { $0.journalLeaks } == 0, "the journal never holds a password")
        let saved = (try? Data(contentsOf: harnessEnvironment!.journal)) ?? Data()
        check(saved.range(of: Data(marker.utf8)) == nil, "the journal never holds a password")
        check(!presenter.texts.contains { $0.contains(marker) }, "no notice holds a password: \(presenter.texts)")
    }

    func finish(keepingFolder: Bool = false) {
        audit()
        controller.stop()
        if !keepingFolder { try? FileManager.default.removeItem(at: folder) }
        UserDefaults().removePersistentDomain(forName: suite)
    }
}

/// Acceptance 1: one question, then list, extract and the done notice, for a ZIP and a 7z.
@MainActor
func rightFirstTime() async throws {
    for (name, stem) in [("Photos.zip", "Photos"), ("Set.7z", "Set")] {
        let rig = try Rig(answers: [right], passwords: [name: right])
        defer { rig.finish() }
        await rig.extract(name)
        check(rig.record.asks == [Record.Ask(title: "Password for \(name)", message: nil, field: "Password",
                                            confirm: "Extract")], "\(rig.record.asks)")
        check(rig.steps == ["list", "list", "extract"], "\(rig.steps)")
        check(rig.calls[0].environment.isEmpty, "the first listing runs without a password")
        check(rig.calls[1...].allSatisfy { $0.environment == [variable: right] }, "then HatchZip gets it")
        check(rig.calls[2].arguments.contains("--keep-archive"), "kept, as by default")
        check(rig.exists("\(stem)/b/c.txt") && rig.exists(name), "\(rig.visible)")
        check(rig.presenter.texts == ["Extracting \(name)", "Extracted \(stem)"], "\(rig.presenter.texts)")
        check(rig.journal().isEmpty, "\(rig.journal())")
    }
}

@MainActor
func wrongThenRight() async throws {
    let rig = try Rig(answers: [wrong, right], passwords: ["Photos.zip": right])
    defer { rig.finish() }
    await rig.extract("Photos.zip")
    check(rig.record.asks.map(\.message) == [nil, "That password did not work."], "\(rig.record.asks)")
    check(rig.record.besideAtAsk == [["Photos.zip"], ["Photos.zip"]], "nothing beside it before: \(rig.record.besideAtAsk)")
    check(rig.exists("Photos/a.txt"), "\(rig.visible)")
}

@MainActor
func threeWrong() async throws {
    let rig = try Rig(answers: [wrong, wrong, wrong, right], passwords: ["Photos.zip": right])
    defer { rig.finish() }
    let before = rig.bytes("Photos.zip")
    await rig.extract("Photos.zip", "Next.zip")
    check(rig.record.asks.count == 3, "exactly three questions: \(rig.record.asks.count)")
    check(rig.presenter.failures == ["The password was not accepted."], "\(rig.presenter.failures)")
    check(rig.bytes("Photos.zip") == before, "the archive is unchanged")
    check(rig.visible == ["Next", "Next.zip", "Photos.zip"], "no staging, and the next one ran: \(rig.visible)")
    check(rig.journal().isEmpty, "\(rig.journal())")
}

@MainActor
func cancelAtQuestion() async throws {
    let rig = try Rig(answers: [nil], passwords: ["Photos.zip": right])
    defer { rig.finish() }
    let before = rig.bytes("Photos.zip")
    await rig.extract("Photos.zip", "Next.zip")
    check(rig.calls.filter { $0.arguments[1].hasSuffix("Photos.zip") }.count == 1, "no tool after Cancel")
    check(rig.presenter.texts.contains("Stopped extracting Photos.zip"), "\(rig.presenter.texts)")
    check(rig.presenter.failures.isEmpty, "\(rig.presenter.failures)")
    check(rig.bytes("Photos.zip") == before && rig.visible == ["Next", "Next.zip", "Photos.zip"], "\(rig.visible)")
    check(rig.journal().isEmpty, "\(rig.journal())")
}

@MainActor
func notAskedWhenNotNeeded() async throws {
    let rig = try Rig()
    defer { rig.finish() }
    await rig.extract("Plain.zip", "src.tar.zst")
    check(rig.record.asks.isEmpty, "no question")
    check(rig.calls.allSatisfy { $0.environment.isEmpty }, "no extra environment")
    check(rig.exists("Plain/a.txt") && rig.exists("src/a.txt"), "\(rig.visible)")
}

@MainActor
func noSpaceWithPassword() async throws {
    var rig = try Rig(answers: [right], passwords: ["Photos.zip": right])
    rig.tools.state.withLock { $0.extractStatuses = [3] }
    await rig.extract("Photos.zip")
    check(rig.steps == ["list", "list", "extract", "check", "extract"], "\(rig.steps)")
    check(rig.calls[3].environment == [variable: right], "check carries the password")
    check(rig.record.confirms.count == 1, "the in-place question is asked")
    check(rig.calls[4].arguments.contains("-y") && rig.calls[4].environment == [variable: right], "and the run in place")
    rig.finish()

    rig = try Rig(answers: [right], passwords: ["Set.7z": right])
    rig.tools.state.withLock { $0.extractStatuses = [3] }
    await rig.extract("Set.7z")
    check(rig.steps == ["list", "list", "extract", "restore"], "no check for a protected 7z: \(rig.steps)")
    check(rig.record.confirms.isEmpty, "no in-place question")
    check(rig.presenter.failures == ["no room"], "\(rig.presenter.failures)")
    rig.finish()

    rig = try Rig(answers: [right], passwords: ["Set.7z": right])
    rig.defaults.set(true, forKey: "archivesInPlace")
    rig.tools.state.withLock { $0.hold = ["Set.7z"] }
    rig.module!.open([rig.archive("Set.7z")])
    while !rig.tools.state.withLock({ $0.heldStarted }) { await Task.yield() }
    check(rig.calls.last!.arguments.contains("--keep-archive"), "a protected 7z is kept despite the option")
    check(rig.tools.state.withLock { $0.journalInPlaceAtExtract } == [false], "the journal says kept first")
    rig.module!.cancel(rig.module!.current!.job.id)
    await rig.module!.drain()
    check(rig.visible == ["Set.7z"], "a stop leaves no staging and places nothing: \(rig.visible)")
    rig.finish()
}

@MainActor
func extractRefusesAfterProvenPassword() async throws {
    let rig = try Rig(answers: [right, right], passwords: ["Photos.rar": right])
    defer { rig.finish() }
    rig.tools.state.withLock { $0.extractStatuses = [5] }
    await rig.extract("Photos.rar")
    check(rig.record.asks.count == 1, "no second round of questions")
    check(rig.presenter.failures == ["The password was not accepted."], "\(rig.presenter.failures)")
}

@MainActor
func noHook() async throws {
    let rig = try Rig(hook: false, passwords: ["Photos.zip": right])
    defer { rig.finish() }
    let before = rig.bytes("Photos.zip")
    await rig.extract("Photos.zip")
    check(rig.presenter.failures == ["The password was not accepted."], "\(rig.presenter.failures)")
    check(rig.steps == ["list"] && rig.bytes("Photos.zip") == before, "\(rig.steps)")
}

@MainActor
func switchOffWhileAsking() async throws {
    let rig = try Rig(answers: [right], passwords: ["Photos.zip": right])
    defer { rig.finish() }
    rig.record.holdAsk = true
    rig.module!.open([rig.archive("Photos.zip")])
    let task = rig.module!.current!.task
    while rig.record.heldAsk == nil { await Task.yield() }
    rig.controller.preferences.set("archives", on: false)
    while rig.module != nil { await Task.yield() }
    rig.record.heldAsk?.resume()
    await task.value
    check(rig.steps == ["list"], "no tool runs once the answer arrives: \(rig.steps)")
    check(rig.journal().map(\.name) == ["Photos.zip"], "the job stays to resume")
}

@MainActor
func resumeAfterRelaunch() async throws {
    for answer in [right, nil] {
        let folder = FileManager.default.temporaryDirectory.appending(path: "nc-archives-pw-\(UUID())")
        let job = ArchiveJob(id: UUID(), archive: folder.appending(path: "Photos.zip"), inPlace: true)
        try FileManager.default.createDirectory(at: job.staging, withIntermediateDirectories: true)
        try Data("archive".utf8).write(to: job.archive)
        try Data("x".utf8).write(to: job.staging.appending(path: "a.txt"))
        try job.staging.path.write(toFile: job.archive.path + ".hatchzip", atomically: true, encoding: .utf8)
        let rig = try Rig(folder: folder, answers: [answer], journal: [job], passwords: ["Photos.zip": right])
        defer { rig.finish() }
        await rig.module!.drain()
        check(rig.record.asks.count == 1, "a resumed job asks again")
        if answer == nil {
            check(rig.steps == ["list", "restore"], "\(rig.steps)")
            check(rig.exists("a.txt") && rig.presenter.texts.contains("Stopped extracting Photos.zip"), "\(rig.visible)")
        } else {
            check(rig.steps == ["list", "list", "extract"] && rig.calls[2].arguments.contains("-y"), "\(rig.steps)")
            check(rig.exists("Photos/b/c.txt"), "\(rig.visible)")
        }
        check(rig.journal().isEmpty, "\(rig.journal())")
    }
}

@MainActor
func eachArchiveAsks() async throws {
    let rig = try Rig(answers: [right, right], passwords: ["One.zip": right, "Two.7z": right])
    defer { rig.finish() }
    await rig.extract("One.zip", "Two.7z")
    check(rig.record.asks.map(\.title) == ["Password for One.zip", "Password for Two.7z"], "\(rig.record.asks)")
    let second = rig.calls.first { $0.arguments[1].hasSuffix("Two.7z") }!
    check(second.environment.isEmpty, "the first password is not reused")
}

/// A 7z with encrypted names stopped mid-way: restore refuses, so the job and its staging stay,
/// unannounced at launch, until the same file is opened again and resumed into that staging.
@MainActor
func stoppedEncryptedNames() async throws {
    var rig = try Rig(answers: [right], passwords: ["Vault.7z": right], hiddenNames: ["Vault.7z"])
    let folder = rig.folder
    rig.tools.state.withLock { $0.hold = ["Vault.7z"] }
    rig.module!.open([rig.archive("Vault.7z")])
    while !rig.tools.state.withLock({ $0.heldStarted }) { await Task.yield() }
    let staging = rig.module!.current!.job.staging
    rig.module!.cancel(rig.module!.current!.job.id)
    await rig.module!.drain()
    check(rig.steps == ["list", "list", "extract", "restore"] && rig.calls[3].environment.isEmpty, "\(rig.steps)")
    check(rig.journal().count == 1 && rig.journal()[0].stopped != nil, "the entry stays, stopped: \(rig.journal())")
    check(rig.staging == [staging.lastPathComponent] && rig.exists("Vault.7z.hatchzip"), "staging kept: \(rig.visible)")
    check(rig.presenter.texts.last == "Stopped extracting Vault.7z", "\(rig.presenter.texts)")
    rig.module!.cancelAll()
    check(rig.journal().count == 1, "Cancel All Extractions keeps it")
    rig.controller.preferences.set("archives", on: false)
    while rig.module != nil { await Task.yield() }
    check(rig.staging.count == 1 && rig.journal().count == 1, "switching off keeps it too")
    rig.finish(keepingFolder: true)

    rig = try Rig(folder: folder, answers: [nil], passwords: ["Vault.7z": right], hiddenNames: ["Vault.7z"])
    await Task.yield()
    check(rig.module!.current == nil && rig.calls.isEmpty && rig.record.asks.isEmpty, "a relaunch asks nothing")
    check(rig.presenter.posts.isEmpty, "and shows nothing running")
    await rig.extract("Vault.7z")
    check(rig.record.asks.count == 1, "opening it again asks")
    check(rig.journal().count == 1 && rig.journal()[0].stopped != nil && rig.staging.count == 1,
          "Cancel there leaves the entry as it was: \(rig.journal())")
    rig.record.answers = [right]
    await rig.extract("Vault.7z")
    let extract = rig.calls.last { $0.arguments[0] == "extract" }!
    check(extract.arguments.contains(staging.path), "resumed into the kept staging: \(extract.arguments)")
    check(rig.exists("Vault/b/c.txt") && rig.staging.isEmpty && !rig.exists("Vault.7z.hatchzip"), "\(rig.visible)")
    check(rig.journal().isEmpty, "\(rig.journal())")
    rig.finish()
}

/// Progress HatchZip holds for a folder we never made (a run by hand, or a file since replaced).
@MainActor
func startedElsewhere() async throws {
    let rig = try Rig(answers: [right], passwords: ["Vault.7z": right])
    defer { rig.finish() }
    try "/elsewhere".write(toFile: rig.archive("Vault.7z").path + ".hatchzip", atomically: true, encoding: .utf8)
    await rig.extract("Vault.7z")
    check(rig.presenter.failures == ["This archive is partly extracted elsewhere; finish that with hatchzip first."],
          "\(rig.presenter.failures)")
    check(!rig.steps.contains("restore") && rig.staging.isEmpty, "the other run's progress is left alone: \(rig.steps)")
    check(rig.exists("Vault.7z.hatchzip"), "\(rig.visible)")
}

/// The real engine on three tiny protected archives, when this Mac has it; else the skip is printed.
func realHatchZip() async throws {
    guard let hatchzip = await ExecutableLocator.locate("hatchzip") else {
        print("SKIP real HatchZip passwords: hatchzip is not installed (brew install xevrion/tap/hatchzip)")
        return
    }
    print("SKIP real HatchZip stop on encrypted names: needs a multi-GB fixture; the PR's probe 3(c) is the proof")
    let secret = "nc-secret-7Qx"
    let root = FileManager.default.temporaryDirectory.appending(path: "nc-archives-pw-real-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root.appending(path: "src"), withIntermediateDirectories: true)
    for (file, text) in [("a", "one"), ("b", "two")] { try Data(text.utf8).write(to: root.appending(path: "src/\(file).txt")) }
    let fixtures: [(String, Data?)] = [
        ("crypto.zip", nil),
        ("aes.zip", Data(base64Encoded: """
            UEsDBDMAAQBjAI1xdV0AAAAAHwAAAAMAAAAFAAsAYS50eHQBmQcAAgBBRQMAAKYZs21vScJxpfuOAhgJzoQGzQtI6x6nnX34c12b1D5QSwMEMwAB\
            AGMAjXF1XQAAAAAfAAAAAwAAAAUACwBiLnR4dAGZBwACAEFFAwAAHy5F529krZLKhBOZjDWaPFLdI4qXDyfQgMEAuejTY1BLAQI/AzMAAQBjAI1x\
            dV0AAAAAHwAAAAMAAAAFAC8AAAAAAAAAIICkgQAAAABhLnR4dAoAIAAAAAAAAQAYAMdl6vK5ed0BAAAAAAAAAAAAAAAAAAAAAAGZBwACAEFFAwAA\
            UEsBAj8DMwABAGMAjXF1XQAAAAAfAAAAAwAAAAUALwAAAAAAAAAggKSBTQAAAGIudHh0CgAgAAAAAAABABgAlWnq8rl53QEAAAAAAAAAAAAAAAAA\
            AAAAAZkHAAIAQUUDAABQSwUGAAAAAAIAAgDEAAAAmgAAAAAA
            """)),
        ("aes.7z", Data(base64Encoded: """
            N3q8ryccAASI2s4uhwAAAAAAAAAhAAAAAAAAAIPqTDwvibsFtEUPpi08+8DRJkp4AACBMweuD87ysgwHsMPa919FiphISviu0zhwQOmxenRQLD0B\
            HLYfDoyz/T3c4gcCy47DCBGKL+oQ5F6wSgEEb7bQhBqj6PcEZZlhBGaMBHMJ97+xkAodFFc3x+xNQ6+jZHt8GVYWqdELNqtxRKmsgSgEBBRNAAAX\
            BhABCXcABwsBAAEjAwEBBV0AEAAADICOCgFd4t40AAA=
            """)),
    ]
    let seen = Mutex<[[String]]>([])
    let extractor = ArchiveExtractor(locate: { $0 == "hatchzip" ? hatchzip : nil }, run: { tool, arguments, extra in
        seen.withLock { $0.append(arguments) }
        return try await ArchiveProcess.run(tool, arguments, environment: extra)
    })
    for (name, data) in fixtures {
        for attempt in [wrong, secret] {
            let folder = root.appending(path: "\(attempt == secret ? "right" : "wrong")-\(name)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let archive = folder.appending(path: name)
            if let data {
                try data.write(to: archive)
            } else {
                let zip = try await ArchiveProcess.run(URL(filePath: "/usr/bin/zip"), [
                    "-q", "-j", "-P", secret, archive.path, root.appending(path: "src/a.txt").path,
                    root.appending(path: "src/b.txt").path])
                check(zip.status == 0, "zip made the fixture: \(zip.errors)")
            }
            let before = try Data(contentsOf: archive)
            let job = ArchiveJob(id: UUID(), archive: archive, inPlace: false)
            seen.withLock { $0.removeAll() }
            do {
                let placed = try await extractor.extract(
                    job, askPassword: { _ in attempt }, askInPlace: { _ in false }, onInPlace: { _ in })
                check(attempt == secret, "\(name): a wrong password extracted")
                let stem = URL(filePath: name).deletingPathExtension().lastPathComponent
                check(placed?.lastPathComponent == stem, "\(name): \(String(describing: placed))")
                let text = try String(contentsOf: placed!.appending(path: "b.txt"), encoding: .utf8)
                check(text == "two", "\(name): the files come out")
            } catch ArchiveFailure.password {
                check(attempt == wrong, "\(name): the right password was refused")
                check(try FileManager.default.contentsOfDirectory(atPath: folder.path) == [name],
                      "\(name): nothing beside it after wrong ones")
            }
            check(try Data(contentsOf: archive) == before, "\(name): the archive is byte-identical")
            check(!seen.withLock { $0 }.joined().contains { $0.contains(marker) }, "\(name): a password in arguments")
        }
    }
    print("real HatchZip passwords: ok")
}

@main
enum ArchivesPasswordTest {
    @MainActor
    static func main() async throws {
        try await rightFirstTime()
        try await wrongThenRight()
        try await threeWrong()
        try await cancelAtQuestion()
        try await notAskedWhenNotNeeded()
        try await noSpaceWithPassword()
        try await extractRefusesAfterProvenPassword()
        try await noHook()
        try await switchOffWhileAsking()
        try await resumeAfterRelaunch()
        try await eachArchiveAsks()
        try await stoppedEncryptedNames()
        try await startedElsewhere()
        try await realHatchZip()
        print("nc-Archives-password-test: ok")
    }
}
