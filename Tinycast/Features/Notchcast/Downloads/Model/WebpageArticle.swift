import Foundation

struct WebpageArticle: Sendable {
    let title: String
    let author: String
    let published: String?
    let source: URL
    let baseURL: URL
    let html: String
    /// Set when a tool already wrote the Markdown, so `html` is not converted.
    var markdownBody: String?

    /// `saved` is the user's own day, so a save just after local midnight is not dated yesterday.
    func markdown(saved: Date, timeZone: TimeZone) -> String {
        let date = saved.formatted(
            Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day().dateSeparator(.dash))
        let body = markdownBody ?? HTMLMarkdown.convert(html, baseURL: baseURL)
        let escapedTitle = title.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        let heading = "# " + HTMLMarkdown.convert("<span>\(escapedTitle)</span>", baseURL: baseURL)
        var lines = ["---", "title: \(Self.quoted(title))", "author: \(Self.quoted(author))",
                     "source: \(Self.quoted(source.absoluteString))"]
        if let published, let day = Self.publicationDay(published) { lines.append("published: \(day)") }
        lines += ["saved: \(date)", "type: article", "---", ""]
        if body.components(separatedBy: "\n").first != heading { lines += [heading, ""] }
        lines += [body, ""]
        return lines.joined(separator: "\n")
    }

    var filename: String {
        let name = "\(author) - \(title)".replacingOccurrences(of: "[/\\\\:*?\"<>|\\p{Cc}]+", with: " ",
                                                           options: .regularExpression)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        var result = ""
        for character in name {
            guard result.utf8.count + String(character).utf8.count <= 200 else { break }
            result.append(character)
        }
        return result.isEmpty ? "article" : result
    }

    /// The first line of a post that has no title of its own, cut at a word.
    static func headline(_ text: String) -> String? {
        guard let line = text.split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { !$0.isEmpty }) else { return nil }
        guard line.count > 80 else { return line }
        let cut = line.prefix(80)
        return String(cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut) + "…"
    }

    static func quoted(_ text: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        guard let data = try? encoder.encode(text), let value = String(data: data, encoding: .utf8) else { return "\"\"" }
        return value
    }

    private static func publicationDay(_ text: String) -> String? {
        let prefix = String(text.prefix(10))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: prefix), formatter.string(from: date) == prefix else { return nil }
        return prefix
    }
}
