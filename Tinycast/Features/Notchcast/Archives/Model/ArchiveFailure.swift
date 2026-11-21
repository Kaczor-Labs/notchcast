import Foundation

nonisolated struct ArchiveProcessResult: Equatable, Sendable {
    var status: Int32
    var output = ""
    var errors = ""
}

/// Every way an extraction or a compression stops short, each with the words the island shows.
nonisolated enum ArchiveFailure: Error, Equatable, Sendable {
    case notArchive(String)
    case missingTool(ArchiveTool)
    case unsafe(ArchiveRefusal)
    case noSpace(String)
    case damaged(String)
    case password
    case failed(String)
    case nothingSelected
    case automationRefused
    case severalFolders
    case notWritable(String)
    case notCompressible(String)
    case busy(String)
    case compressionFailed(String)

    /// HatchZip's documented exit statuses; 130 is a pause, so the caller treats it as a stop.
    static let hatchzipPaused: Int32 = 130
    static let hatchzipNoSpace: Int32 = 3

    static func hatchzip(_ result: ArchiveProcessResult) -> ArchiveFailure? {
        switch result.status {
        case 0: nil
        case hatchzipNoSpace: .noSpace(detail(result))
        case 4: .damaged(detail(result))
        case 5: .password
        default: .failed(detail(result))
        }
    }

    static func tool(_ result: ArchiveProcessResult) -> ArchiveFailure? {
        result.status == 0 ? nil : .failed(detail(result))
    }

    /// The last thing the tool said, without its `error:` prefix.
    static func detail(_ result: ArchiveProcessResult) -> String {
        let said = [result.errors, result.output].lazy
            .compactMap { $0.split(whereSeparator: \.isNewline).last.map(String.init) }.first ?? ""
        let line = said.trimmingCharacters(in: .whitespaces)
        return line.hasPrefix("error: ") ? String(line.dropFirst(7)) : line
    }

    var message: String {
        switch self {
        case .notArchive(let name):
            String(localized: "\(name) is not an archive Notchcast opens.", table: "NotchcastArchives")
        case .missingTool(let tool):
            String(localized: "\(tool.name) is not installed. Install it with: \(tool.installCommand)",
                   table: "NotchcastArchives")
        case .unsafe(let refusal): refusal.message
        case .noSpace(let detail):
            detail.isEmpty ? String(localized: "Not enough free space.", table: "NotchcastArchives") : detail
        case .damaged(let detail):
            detail.isEmpty ? String(localized: "The archive is damaged.", table: "NotchcastArchives") : detail
        case .password:
            String(localized: "This archive needs a password, which Notchcast cannot ask for yet.",
                   table: "NotchcastArchives")
        case .failed(let detail):
            detail.isEmpty ? String(localized: "Extraction failed.", table: "NotchcastArchives") : detail
        case .nothingSelected:
            String(localized: "Select files or folders in Finder first.", table: "NotchcastArchives")
        case .automationRefused:
            String(localized: "Allow Automation access to read the Finder selection.", table: "NotchcastArchives")
        case .severalFolders:
            String(localized: "Select items from one folder.", table: "NotchcastArchives")
        case .notWritable(let folder):
            String(localized: "Notchcast cannot write to \(folder).", table: "NotchcastArchives")
        case .notCompressible(let name):
            String(localized: "\(name) cannot be compressed.", table: "NotchcastArchives")
        case .busy(let name):
            String(localized: "Wait for \(name) to finish.", table: "NotchcastArchives")
        case .compressionFailed(let detail):
            detail.isEmpty ? String(localized: "Compression failed.", table: "NotchcastArchives") : detail
        }
    }
}
