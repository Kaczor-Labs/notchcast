import Foundation

/// Which installed subscription cleans up when the reader picked no model of their own.
enum DictationCleanupModelPolicy {
    enum Source: Sendable { case claude, codex, other }

    /// Claude before Codex, each one's lightest model first: cleanup has ten seconds to answer.
    static func automatic<Option>(
        from options: [Option], source: (Option) -> Source, id: (Option) -> String
    ) -> Option? {
        for wanted in [Source.claude, .codex] {
            let candidates = options.filter { source($0) == wanted }
            if let light = candidates.first(where: { isLight(id($0)) }) { return light }
            if let first = candidates.first { return first }
        }
        return nil
    }

    private static func isLight(_ id: String) -> Bool {
        let id = id.lowercased()
        return id.contains("haiku") || id.contains("mini")
    }
}
