import Foundation

/// The rule lives in `sudo_local`, which survives macOS updates; every other line stays as it was.
enum SudoTouchIDPolicy {
    static let rule = "auth       sufficient     pam_tid.so"

    enum State: Equatable, Sendable {
        case off, on
        /// A pam_tid line the switch did not write and could not put back, so it is left alone.
        case byHand
    }

    /// `sudo` must still pull in `sudo_local`, or the rule there does nothing.
    static func includesLocal(sudo: String) -> Bool {
        sudo.split(separator: "\n", omittingEmptySubsequences: false).contains {
            fields($0) == ["auth", "include", "sudo_local"]
        }
    }

    static func state(local: String?) -> State {
        let lines = (local ?? "").split(separator: "\n", omittingEmptySubsequences: false)
        if lines.contains(where: { !isOurs($0) && fields($0).contains("pam_tid.so") }) { return .byHand }
        return lines.contains(where: isOurs) ? .on : .off
    }

    /// The file's new text, or nil when it already says what was asked or was set up by hand.
    static func change(_ local: String?, enabled: Bool) -> String? {
        let current = state(local: local)
        guard current != .byHand, (current == .on) != enabled else { return nil }
        let text = local ?? ""
        if enabled {
            return text + (text.isEmpty || text.hasSuffix("\n") ? "" : "\n") + rule + "\n"
        }
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !isOurs($0) }.joined(separator: "\n")
    }

    /// Only the bare rule is ours: removing it loses nothing, since On writes it back the same.
    private static func isOurs(_ line: Substring) -> Bool {
        line.split(whereSeparator: \.isWhitespace) == ["auth", "sufficient", "pam_tid.so"]
    }

    private static func fields(_ line: Substring) -> [String] {
        let code = line.prefix { $0 != "#" }
        return code.split(whereSeparator: \.isWhitespace).map(String.init)
    }
}
