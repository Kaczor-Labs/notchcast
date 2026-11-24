import Foundation

protocol DownloadRunner: Sendable {
    var kind: String { get }
    var runsSerially: Bool { get }
    var tools: [DownloadTool] { get }
    func run(_ job: DownloadJob, context: DownloadRunContext) async throws -> URL?
}

extension DownloadRunner {
    var runsSerially: Bool { false }
}

struct DownloadRunPause: LocalizedError {
    let detail: String
    var errorDescription: String? { detail }
}
