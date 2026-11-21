// notchcast-addon-order: 190
// notchcast-readme: Downloads: extract archives in place with HatchZip and compress a Finder selection
// notchcast-new-switch-ids: archives
import SwiftUI

/// Extracts archives in place of Archive Utility and compresses a Finder selection with your tools.
enum ArchivesAddon: NotchcastAddon {
    static let switches = [
        NotchcastSwitch(
            id: "archives",
            title: String(localized: "Archives", table: "NotchcastArchives"),
            subtitle: String(
                localized: "Extract archives with HatchZip and compress a Finder selection, next to the original.",
                table: "NotchcastArchives"),
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
        NotchcastCommand(
            slug: "compress-zip", name: String(localized: "Compress to ZIP", table: "NotchcastArchives"),
            symbol: "doc.zipper", switchID: "archives", keywords: ["compress", "archive", "zip"]
        ) { $0.module(ArchivesModule.self)?.compress(.zip) },
        NotchcastCommand(
            slug: "compress-7z", name: String(localized: "Compress to 7z", table: "NotchcastArchives"),
            symbol: "doc.zipper", switchID: "archives", keywords: ["compress", "archive", "7zip"]
        ) { $0.module(ArchivesModule.self)?.compress(.sevenZip) },
        NotchcastCommand(
            slug: "compress-tar-zst", name: String(localized: "Compress to .tar.zst", table: "NotchcastArchives"),
            symbol: "doc.zipper", switchID: "archives", keywords: ["compress", "archive", "zstd"]
        ) { $0.module(ArchivesModule.self)?.compress(.tarZstd) },
    ]

    static let settings = [
        NotchcastSettingsRow(switchID: "archives") { AnyView(ArchivesSettingsView(context: $0)) }
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        ArchivesModule(context: context, environment: .live())
    }
}
