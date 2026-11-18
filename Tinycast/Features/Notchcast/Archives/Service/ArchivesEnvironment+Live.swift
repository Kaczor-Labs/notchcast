import AppKit
import UniformTypeIdentifiers

extension ArchivesEnvironment {
    private static let archiveUtility = URL(
        filePath: "/System/Library/CoreServices/Applications/Archive Utility.app", directoryHint: .isDirectory)

    static func live() -> Self {
        let opens = ArchiveOpenHandler()
        return Self(
            journal: AppPaths.applicationSupport()
                .appending(path: "Notchcast", directoryHint: .isDirectory).appending(path: "archives.json"),
            extractor: ArchiveExtractor(
                locate: { await ExecutableLocator.locate($0) },
                run: { try await ArchiveProcess.run($0, $1) }),
            routeOpens: { opens.route($0) },
            setDefaultApp: { on in Task { await setDefaultApp(on) } },
            reveal: { NSWorkspace.shared.activateFileViewerSelecting([$0]) },
            pickArchives: pickArchives)
    }

    /// Handing back gives each type Notchcast still holds to Archive Utility, else the next app.
    private static func setDefaultApp(_ on: Bool) async {
        let workspace = NSWorkspace.shared
        let types = ArchiveRoute.defaultExtensions.compactMap { UTType(filenameExtension: $0) }
            .filter { !$0.isDynamic }
        for type in Set(types) {
            let holder = workspace.urlForApplication(toOpen: type)
            if on {
                guard holder != Bundle.main.bundleURL else { continue }
                try? await workspace.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: type)
            } else if holder == Bundle.main.bundleURL {
                let others = workspace.urlsForApplications(toOpen: type).filter { $0 != Bundle.main.bundleURL }
                guard let next = others.first(where: { $0 == archiveUtility }) ?? others.first else { continue }
                try? await workspace.setDefaultApplication(at: next, toOpen: type)
            }
        }
    }

    private static func pickArchives() -> [URL] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.prompt = String(localized: "Extract", table: "NotchcastArchives")
        NSApp.activate()
        return panel.runModal() == .OK ? panel.urls : []
    }
}
