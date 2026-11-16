import Foundation

enum HTMLMarkdown {
    static func convert(_ html: String, baseURL: URL) -> String {
        let document = HTMLDocument(html)
        let raw = render(document.root, baseURL: baseURL).trimmingCharacters(in: .whitespacesAndNewlines)
        return tidied(raw).joined(separator: "\n")
    }

    /// Blank runs outside a code fence shrink to one empty line; a fence keeps its lines as written.
    private static func tidied(_ raw: String) -> [String] {
        var fence: String?
        var lines: [String] = []
        for rawLine in raw.components(separatedBy: "\n") {
            let line = fence == nil && rawLine.allSatisfy(\.isWhitespace) ? "" : rawLine
            if let current = fence {
                lines.append(line)
                if line == current { fence = nil }
            } else {
                if line.hasPrefix("```") { fence = String(line.prefix(while: { $0 == "`" })) }
                if !line.isEmpty || lines.last != "" { lines.append(line) }
            }
        }
        return lines
    }

    private static func render(_ node: HTMLDocument.Node, baseURL: URL, depth: Int = 0) -> String {
        guard depth < 128, !HTMLDocument.dropped.contains(node.tag), node.attributes["hidden"] == nil,
              node.attributes["aria-hidden"] != "true" else { return "" }
        if node.tag == "#text" { return escape(collapsed(node.text)) }
        if node.tag == "pre" {
            let text = node.plainText.trimmingCharacters(in: .newlines)
            let fence = String(repeating: "`", count: max(3, longestBackticks(text) + 1))
            return "\n\n\(fence)\(language(of: node))\n\(text)\n\(fence)\n\n"
        }
        if node.tag == "code" {
            let text = collapsed(node.plainText)
            let fence = String(repeating: "`", count: max(1, longestBackticks(text) + 1))
            let padding = text.contains("`") || text.hasPrefix(" ") || text.hasSuffix(" ") ? " " : ""
            return "\(fence)\(padding)\(text)\(padding)\(fence)"
        }
        if node.tag == "ul" || node.tag == "ol" { return list(node, baseURL: baseURL, depth: depth) }
        if node.tag == "table" { return table(node, baseURL: baseURL, depth: depth) }
        let content = children(of: node, baseURL: baseURL, depth: depth, lineStart: blockTags.contains(node.tag))
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        switch node.tag {
        case "h1", "h2", "h3", "h4", "h5", "h6":
            return "\n\n\(String(repeating: "#", count: Int(node.tag.suffix(1)) ?? 1)) \(collapsed(trimmed))\n\n"
        case "p", "div", "section", "article", "main", "header", "figure", "figcaption", "dl", "dt", "dd":
            return trimmed.isEmpty ? "" : "\n\n\(trimmed)\n\n"
        case "br": return "  \n"
        case "hr": return "\n\n---\n\n"
        case "strong", "b": return outlined(content, trimmed) { "**\($0)**" }
        case "em", "i": return outlined(content, trimmed) { "*\($0)*" }
        case "del", "s": return outlined(content, trimmed) { "~~\($0)~~" }
        case "blockquote":
            return "\n\n" + tidied(trimmed).map { $0.isEmpty ? ">" : "> \($0)" }.joined(separator: "\n") + "\n\n"
        case "a":
            guard !trimmed.isEmpty else { return outlined(content, trimmed) { $0 } }
            guard let url = absolute(node.attributes["href"], baseURL: baseURL, image: false) else { return content }
            let label = content.contains("\n")
                ? collapsed(trimmed.split(separator: "\n").map {
                    listed($0.replacingOccurrences(of: "^(#{1,6} |> ?)", with: "", options: .regularExpression))
                }.filter { !$0.isEmpty }.joined(separator: " "))
                : collapsed(trimmed)
            return outlined(content, trimmed) { _ in "[\(label)](<\(url)>)" }
        case "img":
            guard let url = absolute(imageSource(node), baseURL: baseURL, image: true) else { return "" }
            return "![\(escape(node.attributes["alt"] ?? ""))](<\(url)>)"
        default: return content
        }
    }

    private static func list(_ node: HTMLDocument.Node, baseURL: URL, depth: Int) -> String {
        var number = Int(node.attributes["start"] ?? "") ?? 1
        let items = node.children.filter { $0.tag == "li" }.map { item in
            let marker = node.tag == "ol" ? "\(number). " : "- "
            number += 1
            let text = children(of: item, baseURL: baseURL, depth: depth, lineStart: true)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let lines = text.components(separatedBy: "\n")
            return marker + lines.enumerated().map { index, line in
                index == 0 ? line : String(repeating: " ", count: marker.count) + line
            }.joined(separator: "\n")
        }
        return "\n\n" + items.joined(separator: "\n") + "\n\n"
    }

    private static func table(_ node: HTMLDocument.Node, baseURL: URL, depth: Int) -> String {
        let rows = node.descendants(tag: "tr").map { row in
            row.children.filter { $0.tag == "th" || $0.tag == "td" }.map { cell in
                render(cell, baseURL: baseURL, depth: depth + 1)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "|", with: "\\|")
                    .replacingOccurrences(of: "\n", with: " ")
            }
        }.filter { !$0.isEmpty }
        let caption = node.children.first { $0.tag == "caption" }
            .map { children(of: $0, baseURL: baseURL, depth: depth, lineStart: true) }
            .map { collapsed($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? ""
        let title = caption.isEmpty ? "" : "\n\n\(caption)\n\n"
        guard let width = rows.map(\.count).max(), width > 0 else { return title }
        let formatted = rows.map { row in "| " + (row + Array(repeating: "", count: width - row.count))
            .joined(separator: " | ") + " |" }
        let divider = "| " + Array(repeating: "---", count: width).joined(separator: " | ") + " |"
        return title + "\n\n" + ([formatted[0], divider] + formatted.dropFirst()).joined(separator: "\n") + "\n\n"
    }

    private static func imageSource(_ node: HTMLDocument.Node) -> String? {
        let source = node.attributes["src"] ?? ""
        if !source.isEmpty, !source.hasPrefix("data:") { return source }
        return node.attributes["data-src"] ?? node.attributes["data-original"]
            ?? largest(node.attributes["srcset"]) ?? largest(node.attributes["data-srcset"])
    }

    /// The widest `w` or densest `x` candidate; one without a descriptor counts as `1x`.
    private static func largest(_ srcset: String?) -> String? {
        let candidates = (srcset ?? "").split(separator: ",").compactMap { candidate -> (url: String, size: Double)? in
            let parts = candidate.split(whereSeparator: \.isWhitespace)
            guard let url = parts.first else { return nil }
            let size = parts.dropFirst().first.flatMap { Double($0.dropLast()) } ?? 1
            return (String(url), size)
        }
        return candidates.reduce(nil as (url: String, size: Double)?) { best, next in
            best.map { $0.size >= next.size ? $0 : next } ?? next
        }?.url
    }

    private static let blockTags: Set<String> = [
        "p", "div", "section", "article", "main", "header", "figure", "figcaption", "dl", "dt", "dd",
        "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "ul", "ol", "li", "table", "pre", "hr", "br",
    ]

    /// With `lineStart`, text opening a block is kept from reading as a list marker.
    private static func children(of node: HTMLDocument.Node, baseURL: URL, depth: Int, lineStart: Bool) -> String {
        var opening = lineStart
        return node.children.map { child in
            let part = render(child, baseURL: baseURL, depth: depth + 1)
            guard opening, !part.allSatisfy(\.isWhitespace) else { return part }
            opening = false
            return blockTags.contains(child.tag) ? part : unlisted(part)
        }.joined()
    }

    private static func unlisted(_ text: String) -> String {
        text.replacingOccurrences(of: "^(\\s*\\d+)([.)])(?=\\s|$)", with: "$1\\\\$2", options: .regularExpression)
            .replacingOccurrences(of: "^(\\s*)([-+])(?=\\s|$)", with: "$1\\\\$2", options: .regularExpression)
    }

    /// Undoes `unlisted` inside a link label, which never starts a line.
    private static func listed(_ text: String) -> String {
        text.replacingOccurrences(of: "^(\\s*\\d+)\\\\([.)])(?=\\s|$)", with: "$1$2", options: .regularExpression)
            .replacingOccurrences(of: "^(\\s*)\\\\([-+])(?=\\s|$)", with: "$1$2", options: .regularExpression)
    }

    /// Edge whitespace stays outside the markers, where Markdown still reads it as a space.
    private static func outlined(_ content: String, _ trimmed: String, _ wrap: (String) -> String) -> String {
        let lead = content.first?.isWhitespace == true ? " " : ""
        guard !trimmed.isEmpty else { return lead }
        let trail = content.last?.isWhitespace == true ? " " : ""
        return lead + wrap(trimmed) + trail
    }

    private static func language(of pre: HTMLDocument.Node) -> String {
        let code = pre.children.first { $0.tag != "#text" }
        return [pre, code].compactMap { $0?.attributes["class"] }.lazy
            .flatMap { $0.split(whereSeparator: \.isWhitespace) }
            .first { $0.hasPrefix("language-") }.map { String($0.dropFirst(9)) } ?? ""
    }

    private static func absolute(_ value: String?, baseURL: URL, image: Bool) -> String? {
        guard let value, let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines),
                                      relativeTo: baseURL)?.absoluteURL,
              let scheme = url.scheme?.lowercased(),
              (image ? ["http", "https"] : ["http", "https", "mailto", "tel"]).contains(scheme) else { return nil }
        return url.absoluteString.replacingOccurrences(of: "<", with: "%3C").replacingOccurrences(of: ">", with: "%3E")
    }

    private static func collapsed(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private static func escape(_ text: String) -> String {
        text.reduce(into: "") { output, character in
            if "\\`*_[]#<>".contains(character) { output.append("\\") }
            output.append(character)
        }
    }

    private static func longestBackticks(_ text: String) -> Int {
        text.split(whereSeparator: { $0 != "`" }).map(\.count).max() ?? 0
    }
}
