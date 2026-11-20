import Foundation
import Synchronization

/// Finding a CLI asks the login shell, so each is found once and found again only once its file is gone.
final class AgentsLocator: Sendable {
    private let find: @Sendable (String) async -> URL?
    private let found = Mutex<[String: URL]>([:])

    init(find: @escaping @Sendable (String) async -> URL? = { await ExecutableLocator.locate($0) }) {
        self.find = find
    }

    /// A CLI that moved (a reinstall, a Node switch) is found again in the same read, never reported missing.
    func locate(_ command: String) async -> URL? {
        if let url = found.withLock({ $0[command] }), FileManager.default.isExecutableFile(atPath: url.path) {
            return url
        }
        let url = await find(command)
        found.withLock { $0[command] = url }
        return url
    }
}
