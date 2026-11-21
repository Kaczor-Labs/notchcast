import AppKit
import CoreServices
import UniformTypeIdentifiers

extension ArchivesEnvironment {
    private static let archiveUtility = URL(
        filePath: "/System/Library/CoreServices/Applications/Archive Utility.app", directoryHint: .isDirectory)

    static func live() -> Self {
        Self(
            journal: AppPaths.applicationSupport()
                .appending(path: "Notchcast", directoryHint: .isDirectory).appending(path: "archives.json"),
            extractor: ArchiveExtractor(
                locate: { await ExecutableLocator.locate($0) },
                run: { try await ArchiveProcess.run($0, $1, environment: $2) }),
            compressor: ArchiveCompressor(
                locate: { await ExecutableLocator.locate($0) },
                run: { try await ArchiveProcess.run($0, $1) }),
            finderSelection: finderSelection,
            setDefaultApp: { on in Task { await setDefaultApp(on) } },
            reveal: { NSWorkspace.shared.activateFileViewerSelecting([$0]) },
            pickArchives: pickArchives)
    }

    /// Automation refused is our own failure; no Finder, no selection or a timeout read as nothing.
    @concurrent
    private static func finderSelection() async throws -> [URL] {
        try NotchcastAppleEvents.finderSelection { status in
            if NotchcastAppleEvents.refused.contains(status) { throw ArchiveFailure.automationRefused }
        }.compactMap { URL(string: $0) }
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

    private static func pickArchives() async -> [URL] {
        guard !Task.isCancelled, NSApp.modalWindow == nil else { return [] }
        let previousApp = NSApp.isActive ? nil : NSWorkspace.shared.menuBarOwningApplication
        defer {
            if let previousApp, previousApp != .current, NSApp.isActive, NSApp.modalWindow == nil {
                NSApp.yieldActivation(to: previousApp)
                previousApp.activate(from: .current, options: [])
            }
        }
        if !NSApp.isActive {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.addsToRecentItems = false
            configuration.promptsUserIfNeeded = false
            // An activation event brings us forward without reopening the palette.
            configuration.appleEvent = NSAppleEventDescriptor(
                eventClass: kCoreEventClass, eventID: kAEActivate, targetDescriptor: nil,
                returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
            _ = try? await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
            guard !Task.isCancelled, NSApp.modalWindow == nil else { return [] }
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.prompt = String(localized: "Extract", table: "NotchcastArchives")
        panel.level = .modalPanel
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        return panel.runModal() == .OK ? panel.urls : []
    }
}
