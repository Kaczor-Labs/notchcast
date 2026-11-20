import Foundation

/// A device Taildrop can send to: one line of `tailscale file cp --targets`.
nonisolated struct TaildropTarget: Equatable, Sendable {
    let address: String
    let name: String
    let isOnline: Bool

    /// Built from the name alone, so a hotkey bound to a device survives every refresh.
    var slug: String {
        let words = name.lowercased().split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
        return (["taildrop-to"] + words.map(String.init)).joined(separator: "-")
    }

    /// Address, name, then a note only when the device is not online; any other line is skipped.
    static func parse(_ output: String) -> [TaildropTarget] {
        var slugs: Set<String> = []
        return output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count >= 2, isAddress(fields[0]), !fields[1].isEmpty else { return nil }
            let target = TaildropTarget(
                address: fields[0], name: fields[1], isOnline: fields.count == 2 || fields[2].isEmpty)
            return slugs.insert(target.slug).inserted ? target : nil
        }
    }

    /// The address becomes a CLI argument, so only an IPv4 or IPv6 literal passes.
    private static func isAddress(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isHexDigit || $0 == "." || $0 == ":" }
    }
}
