// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandNoticeQueue.swift
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
// notchcast-sources: Tests/nc-Archives-module-fixture.swift

import Foundation
import Synchronization

@MainActor
func keepsByDefault() async throws {
    let rig = try Rig()
    defer { rig.finish() }
    let archive = rig.archive("Game.zip", listing: twoFiles)
    rig.module!.open([archive])
    await rig.module!.drain()
    check(rig.visible == ["Game", "Game.zip"], "several items land in a folder beside the kept archive: \(rig.visible)")
    check(rig.exists("Game/b/c.txt"), "the tree is kept")
    check(rig.calls.map { Array($0.prefix(2)) } == [["hatchzip", "list"], ["hatchzip", "extract"]], "\(rig.calls)")
    check(rig.calls[1].contains("--keep-archive") && !rig.calls[1].contains("-y"), "keeping is the default")
    check(rig.presenter.texts == ["Extracting Game.zip", "Extracted Game"], "\(rig.presenter.texts)")
    check(rig.presenter.posts[0].notice.progress != nil, "the running job shows progress")
    rig.presenter.posts[1].onTap?()
    check(rig.record.reveals.map(\.path) == [rig.folder.appending(path: "Game").path], "the notice shows the result")
    check(rig.journal().isEmpty, "a finished job leaves the journal")

    rig.tools.state.withLock { $0.files = ["Game"] }
    rig.module!.open([rig.archive("Again.zip", listing: twoFiles)])
    await rig.module!.drain()
    check(rig.exists("Game 2") && rig.exists("Game"), "one item never replaces an existing name: \(rig.visible)")
    check(!rig.visible.contains { $0.hasPrefix(".notchcast-extract-") }, "no staging folder is left: \(rig.visible)")
}

@MainActor
func refusesBeforeWriting() async throws {
    let rig = try Rig()
    defer { rig.finish() }
    let evil = """
              Size  Name
               1 B  ../evil
        1 entry, 1 B uncompressed, 7 B zip archive
        """
    rig.module!.open([rig.archive("evil.zip", listing: evil)])
    await rig.module!.drain()
    check(rig.calls.count == 1 && rig.calls[0][1] == "list", "only the listing ran: \(rig.calls)")
    check(rig.visible == ["evil.zip"], "nothing was written: \(rig.visible)")
    check(rig.presenter.failures.count == 1 && rig.presenter.failures[0].contains("../evil"), "\(rig.presenter.failures)")

    rig.module!.open([rig.archive("notes.txt")])
    check(rig.presenter.failures.last == "notes.txt is not an archive Notchcast opens.", "\(rig.presenter.failures)")
}

@MainActor
func missingTool() async throws {
    let rig = try Rig()
    defer { rig.finish() }
    rig.tools.state.withLock { $0.installed = [] }
    rig.module!.open([rig.archive("Old.sit"), rig.archive("Game.7z")])
    await rig.module!.drain()
    check(rig.calls.isEmpty, "no program runs: \(rig.calls)")
    check(rig.presenter.failures == ["unar is not installed. Install it with: brew install unar",
                                     "hatchzip is not installed. Install it with: brew install xevrion/tap/hatchzip"],
          "each missing tool is named with its install line: \(rig.presenter.failures)")
}

@MainActor
func asksBeforeInPlace() async throws {
    let rig = try Rig()
    defer { rig.finish() }
    rig.tools.state.withLock { $0.extractStatuses = [3] }
    rig.module!.open([rig.archive("Big.zip", listing: twoFiles)])
    await rig.module!.drain()
    check(rig.record.questions.count == 1 && rig.record.questions[0].contains("required 29.9 MB"),
          "asked once with HatchZip's plan")
    let steps = rig.calls.map { $0[1] }
    check(steps == ["list", "extract", "check", "extract"], "\(steps)")
    check(rig.calls[3].contains("-y") && !rig.calls[3].contains("--keep-archive"), "the second run is in place")
    check(rig.tools.state.withLock { $0.journalInPlaceAtExtract } == [false, true],
          "the journal says in place before the archive starts being consumed")
    check(rig.exists("Big"), "the files are placed")

    rig.record.answer = false
    rig.tools.state.withLock { $0.extractStatuses = [3] }
    rig.module!.open([rig.archive("Huge.zip", listing: twoFiles)])
    await rig.module!.drain()
    check(rig.presenter.failures == ["no room"], "a no leaves a no-space report: \(rig.presenter.failures)")
    check(rig.exists("Huge.zip") && !rig.exists("Huge"), "the archive stays and nothing is placed: \(rig.visible)")
    check(!rig.visible.contains { $0.hasPrefix(".notchcast-extract-") }, "no staging folder is left: \(rig.visible)")

    rig.defaults.set(true, forKey: "archivesInPlace")
    rig.module!.open([rig.archive("Fast.zip", listing: twoFiles)])
    await rig.module!.drain()
    check(rig.calls.last!.contains("-y"), "the option makes in place the default")
}

@MainActor
func fallbackEngines() async throws {
    let rig = try Rig()
    defer { rig.finish() }
    let tar = "-rw-r--r--  0 me  staff  1 Jan  1 12:00 a.txt\n-rw-r--r--  0 me  staff  1 Jan  1 12:00 b/c.txt\n"
    let lsar = #"{"lsarContents":[{"XADFileName":"a.txt","XADFileSize":1},{"XADFileName":"b/c.txt","XADFileSize":1}]}"#
    rig.module!.open([rig.archive("src.tar.zst", listing: tar), rig.archive("Old.sit", listing: lsar),
                      rig.archive("dump.txt.gz")])
    await rig.module!.drain()
    let tools = rig.calls.map { "\($0[0]) \($0[1])" }
    check(tools == ["bsdtar -tvf", "bsdtar -xf", "lsar -j", "unar -o", "sh -c"], "\(tools)")
    check(rig.exists("src/b/c.txt") && rig.exists("Old/a.txt") && rig.exists("dump.txt"), "\(rig.visible)")
}

/// Files opened with the app come through the core's claimers, beside Downloads' `.torrent` one.
@MainActor
func opensThroughTheCore() async throws {
    let rig = try Rig()
    defer { rig.finish() }
    check(rig.controller.open(rig.archive("Game.zip", listing: twoFiles)), "an archive opened with the app is claimed")
    await rig.module!.drain()
    check(rig.exists("Game/a.txt"), "and extracted: \(rig.visible)")
    check(!rig.controller.open(rig.archive("film.torrent")), "a .torrent is left for Downloads")
    check(!rig.controller.open(URL(string: "https://example.com/Game.zip")!), "a web link is not a file to extract")
    check(rig.presenter.failures.isEmpty, "a file left to another add-on gets no refusal: \(rig.presenter.failures)")
    rig.controller.preferences.set("archives", on: false)
    while rig.module != nil { await Task.yield() }
    check(!rig.controller.open(rig.archive("Late.zip", listing: twoFiles)), "switched off, opens fall through to the system")
}

/// Only HatchZip consumes its archive, so only its half-done output is kept after a failure.
func abandonKeepsOnlyHatchZipWork() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "nc-archives-abandon-\(UUID())")
    defer { try? FileManager.default.removeItem(at: folder) }
    let tools = FakeTools(journal: folder.appending(path: "none.json"))
    let extractor = ArchiveExtractor(
        locate: { tools.locate($0) }, run: { tool, arguments, _ in try await tools.run(tool, arguments) })
    func abandoned(_ name: String) async throws -> URL? {
        let job = ArchiveJob(id: UUID(), archive: folder.appending(path: name), inPlace: true)
        try FileManager.default.createDirectory(at: job.staging, withIntermediateDirectories: true)
        try Data("half".utf8).write(to: job.staging.appending(path: "part.bin"))
        let placed = await extractor.abandon(job).placed
        check(!FileManager.default.fileExists(atPath: job.staging.path), "\(name): no staging folder is left")
        return placed
    }
    for name in ["src.tar.zst", "Old.sit", "dump.gz"] {
        let placed = try await abandoned(name)
        check(placed == nil, "\(name): a half-written fallback run is dropped: \(String(describing: placed))")
    }
    let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
    check(files.isEmpty, "nothing was placed beside the untouched archives: \(files)")
    let kept = try await abandoned("Game.zip")
    check(kept?.lastPathComponent == "part.bin", "HatchZip's in-place work is kept")
}

/// The real `sh` and `gzip`: a single compressed file is cut off at the cap instead of filling the disk.
func capsSingleStreams() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "nc-archives-cap-\(UUID())")
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data(count: 1_000_000).write(to: folder.appending(path: "zeros"))
    let gzip = URL(filePath: "/usr/bin/gzip")
    let packed = try await ArchiveProcess.run(gzip, [folder.appending(path: "zeros").path])
    check(packed.status == 0, "gzip made the fixture: \(packed.errors)")
    func unpack(blocks: Int64) async throws -> (status: Int32, size: Int) {
        let arguments = ArchiveCommandLine.extract(
            .gzip, tool: gzip, archive: folder.appending(path: "zeros.gz"), staging: folder, stem: "out",
            inPlace: false, outputBlocks: blocks)
        let result = try await ArchiveProcess.run(URL(filePath: "/bin/sh"), arguments)
        return (result.status, try Data(contentsOf: folder.appending(path: "out")).count)
    }
    let capped = try await unpack(blocks: 8)
    check(capped.status != 0 && capped.size == 8 * 1024, "over the cap the tool is stopped at it: \(capped)")
    let whole = try await unpack(blocks: ArchiveSafety.outputBlocks(archiveSize: 1_000))
    check(whole.status == 0 && whole.size == 1_000_000, "under the cap it runs as before: \(whole)")
}

/// The real engine, once, when this Mac has it; otherwise the skip is printed, never a silent pass.
func realHatchZip() async throws {
    guard let hatchzip = await ExecutableLocator.locate("hatchzip") else {
        print("SKIP real HatchZip extraction: hatchzip is not installed (brew install xevrion/tap/hatchzip)")
        return
    }
    let folder = FileManager.default.temporaryDirectory.appending(path: "nc-archives-real-\(UUID())")
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder.appending(path: "src/one"), withIntermediateDirectories: true)
    try Data("hello".utf8).write(to: folder.appending(path: "src/one/a.txt"))
    try Data("top".utf8).write(to: folder.appending(path: "src/top.txt"))
    let zip = try await ArchiveProcess.run(URL(filePath: "/usr/bin/ditto"), [
        "-c", "-k", "--norsrc", folder.appending(path: "src").path, folder.appending(path: "Real.zip").path])
    check(zip.status == 0, "ditto made the fixture: \(zip.errors)")
    let extractor = ArchiveExtractor(
        locate: { $0 == "hatchzip" ? hatchzip : nil }, run: { try await ArchiveProcess.run($0, $1, environment: $2) })
    let job = ArchiveJob(id: UUID(), archive: folder.appending(path: "Real.zip"), inPlace: false)
    let staged = try await extractor.extract(job, askPassword: nil, askInPlace: { _ in false }, onInPlace: { _ in })
    let placed = try extractor.place(staged.job, stem: staged.stem)
    check(placed?.lastPathComponent == "Real", "placed as a folder: \(String(describing: placed))")
    check(FileManager.default.fileExists(atPath: folder.appending(path: "Real/one/a.txt").path), "files extracted")
    check(FileManager.default.fileExists(atPath: job.archive.path), "the archive is kept")
    print("real HatchZip extraction: ok")
}

/// Compression has its own one-at-a-time slot, so it never waits behind the extraction queue.
@MainActor
func compressesBesideExtraction() async throws {
    let rig = try Rig()
    defer { rig.finish() }
    let notes = rig.folder.appending(path: "notes.txt")
    try Data("notes".utf8).write(to: notes)
    rig.record.selection = [notes]
    rig.module!.open([rig.archive("Game.zip", listing: twoFiles)])
    rig.module!.compress(.zip)
    check(rig.module!.current != nil && rig.module!.compression != nil, "both run side by side")
    await rig.module!.drain()
    await rig.module!.drainCompression()
    check(rig.exists("Game/b/c.txt") && rig.exists("notes.txt.zip"), "both finish: \(rig.visible)")
    for text in ["Extracting Game.zip", "Extracted Game", "Compressing notes.txt.zip", "Compressed notes.txt.zip"] {
        check(rig.presenter.texts.contains(text), "\(text) was shown: \(rig.presenter.texts)")
    }
    check(rig.presenter.failures.isEmpty, "\(rig.presenter.failures)")
}

@main
enum ArchivesModuleTest {
    @MainActor
    static func main() async throws {
        try await keepsByDefault()
        try await refusesBeforeWriting()
        try await missingTool()
        try await asksBeforeInPlace()
        try await fallbackEngines()
        try await opensThroughTheCore()
        try await compressesBesideExtraction()
        try await abandonKeepsOnlyHatchZipWork()
        try await capsSingleStreams()
        try await realHatchZip()
        print("nc-Archives-module-test: ok")
    }
}
