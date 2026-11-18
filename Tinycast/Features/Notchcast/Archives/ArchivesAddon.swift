// notchcast-new-switch-ids: archives
import SwiftUI

/// Extracts opened archives with HatchZip or the user's fallback tools, instead of Archive Utility.
enum ArchivesAddon: NotchcastAddon {
    static let switches = [
        NotchcastSwitch(
            id: "archives",
            title: String(localized: "Archives", table: "NotchcastArchives"),
            subtitle: String(
                localized: "Extract archives with HatchZip, next to the archive.", table: "NotchcastArchives"),
            category: .filesDownloads)
    ]

    static let commands = [
        NotchcastCommand(
            slug: "extract-archive", name: String(localized: "Extract Archive…", table: "NotchcastArchives"),
            symbol: "archivebox", switchID: "archives", keywords: ["unzip", "hatchzip"]
        ) { $0.module(ArchivesModule.self)?.pickAndOpen() },
        NotchcastCommand(
            slug: "cancel-all-extractions",
            name: String(localized: "Cancel All Extractions", table: "NotchcastArchives"),
            symbol: "xmark.circle", switchID: "archives"
        ) { $0.module(ArchivesModule.self)?.cancelAll() },
    ]

    static let settings = [
        NotchcastSettingsRow(switchID: "archives") { AnyView(ArchivesSettingsView(context: $0)) }
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        ArchivesModule(context: context, environment: .live())
    }
}
