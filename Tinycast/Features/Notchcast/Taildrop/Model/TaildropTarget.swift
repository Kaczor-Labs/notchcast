import Foundation

/// A device `tailscale file cp --targets` lists: the user's own, able to receive, never this Mac.
struct TaildropTarget: Equatable, Sendable {
    let address: String
    let name: String

    /// Keyed by the address, which outlives a rename, so a device keeps its alias and hotkey.
    var slug: String {
        "taildrop-" + address.lowercased().split { !$0.isHexDigit }.joined(separator: "-")
    }

    /// `file cp` wants `<target>:`, and an IPv6 address only inside brackets.
    var destination: String { address.contains(":") ? "[\(address)]:" : address + ":" }

    /// The listing's own shape, so a saved list is read back by `parse`.
    var line: String { address + "\t" + name }

    /// One device per line: address, name, then a status column unless it is online.
    static func parse(_ listing: String) -> [TaildropTarget] {
        var seen = Set<String>()
        return listing.split(whereSeparator: \.isNewline).compactMap { line in
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard columns.count >= 2, !columns[1].isEmpty, isAddress(columns[0]),
                seen.insert(columns[0]).inserted
            else { return nil }
            return TaildropTarget(address: columns[0], name: columns[1])
        }
    }

    private static func isAddress(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isHexDigit || $0 == "." || $0 == ":" }
    }
}
