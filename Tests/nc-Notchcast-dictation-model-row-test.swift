// notchcast-sources: Tinycast/Features/Dictation/Model/DictationModel.swift
// notchcast-sources: Tinycast/Features/Dictation/Model/DictationIdleRelease.swift
// notchcast-sources: Tinycast/Features/Dictation/Service/DictationWire.swift Tinycast/Platform/PipeFraming.swift
// notchcast-sources: Tinycast/Features/Dictation/Service/DictationWorker.swift
// notchcast-sources: Tinycast/Features/Dictation/Service/DictationModelStore.swift
// notchcast-sources: Tinycast/Features/Dictation/Service/DictationModelDownloader.swift
// notchcast-sources: Tinycast/Platform/ProcessExit.swift Tinycast/Platform/AppPaths.swift
// notchcast-sources: Tinycast/Features/Notchcast/NotchcastDictationModelSizes.swift
import Foundation
import Observation

/// #1519: the Dictation tab's model row reads the main app's store, never the Settings process's copy.
@main
@MainActor
struct DictationModelRowTest {
    static var failures = 0

    static func check(_ name: String, _ value: Bool) {
        if !value { failures += 1; print("FAIL \(name)") }
    }

    static func row(_ store: DictationModelStore, _ sizes: NotchcastDictationModelSizes) -> NotchcastDictationModelRow {
        NotchcastDictationModelRow(
            model: .ultra, installed: store.installedModels, downloading: store.downloading,
            received: nil, total: nil, sizes: sizes.sizes)
    }

    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "nc-dictation-row-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        // The Settings process builds its store at launch, before the main app finishes the download.
        let settingsProcess = DictationModelStore(idleRelease: .never, root: root)
        let mainApp = DictationModelStore(idleRelease: .never, root: root)
        let sizes = NotchcastDictationModelSizes(store: mainApp)
        sizes.start()
        defer { sizes.stop() }
        check("before the download the row offers it at the approximate size",
              row(mainApp, sizes) == .notInstalled(approximateBytes: 632_000_000))

        let directory = root.appending(path: DictationModel.ultra.folderName)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in DictationModel.ultra.requiredFiles {
            try Data(repeating: 1, count: 3).write(to: directory.appending(path: name))
        }
        try Data(repeating: 1, count: 10).write(to: directory.appending(path: "extra.bin"))
        let measured = Int64(DictationModel.ultra.requiredFiles.count * 3 + 10)
        mainApp.refreshInstalledModels()
        for await size in Observations({ sizes.sizes[.ultra] }) where size != nil { break }
        check("after the main app's rescan the row reads Installed with the measured size",
              row(mainApp, sizes) == .installed(bytes: measured))
        let stale = await settingsProcess.installedSize(.ultra)
        check("the Settings process's own store still knows nothing, so it can't be the source", stale == nil)

        check("a download in the main app shows its progress",
              NotchcastDictationModelRow(
                  model: .ultra, installed: [], downloading: .ultra, received: 5, total: 10, sizes: [:])
                  == .downloading(received: 5, total: 10))
        check("another model's download leaves this row alone",
              NotchcastDictationModelRow(
                  model: .ultra, installed: [.ultra], downloading: .redux, received: 5, total: 10,
                  sizes: [.ultra: measured]) == .installed(bytes: measured))

        try await mainApp.delete(.ultra)
        for await size in Observations({ sizes.sizes[.ultra] }) where size == nil { break }
        check("Remove takes the row back to Not installed",
              row(mainApp, sizes) == .notInstalled(approximateBytes: 632_000_000))
        if failures > 0 { exit(1) }
        print("PASSED")
    }
}
