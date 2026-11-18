import Foundation

/// The rule lives in `sudo_local`, which survives macOS updates; every other line stays as it was.
enum SudoTouchIDPolicy {
    static let rule = "auth       sufficient     pam_tid.so"

    /// `sudo` must still pull in `sudo_local`, or the rule there does nothing.
    static func includesLocal(sudo: String) -> Bool {
        sudo.split(separator: "\n", omittingEmptySubsequences: false).contains {
            fields($0) == ["auth", "include", "sudo_local"]
        }
    }

    static func isEnabled(local: String?) -> Bool {
        (local ?? "").split(separator: "\n", omittingEmptySubsequences: false).contains(where: isRule)
    }

    /// The file's new text, or nil when it already says what was asked, so nothing is written.
    static func change(_ local: String?, enabled: Bool) -> String? {
        guard isEnabled(local: local) != enabled else { return nil }
        let text = local ?? ""
        if enabled {
            return text + (text.isEmpty || text.hasSuffix("\n") ? "" : "\n") + rule + "\n"
        }
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !isRule($0) }.joined(separator: "\n")
    }

    /// Options after the module (`ignore_ssh`) still count; a commented-out rule does not.
    private static func isRule(_ line: Substring) -> Bool {
        let tokens = fields(line)
        return tokens.count >= 3 && Array(tokens.prefix(3)) == ["auth", "sufficient", "pam_tid.so"]
    }

    private static func fields(_ line: Substring) -> [String] {
        let code = line.prefix { $0 != "#" }
        return code.split(whereSeparator: \.isWhitespace).map(String.init)
    }
}
