import Foundation

/// A Distill note for the Markdown folder: title, source and day saved in front matter, then the text.
nonisolated enum DistillNote {
    /// `saved` is the user's own day, as a saved webpage's is.
    static func markdown(title: String, source: String, saved: Date, timeZone: TimeZone, body: String) -> String {
        let day = saved.formatted(
            Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day().dateSeparator(.dash))
        return ["---", "title: \(WebpageArticle.quoted(title))", "source: \(WebpageArticle.quoted(source))",
                "saved: \(day)", "---", "", body.trimmingCharacters(in: .whitespacesAndNewlines), ""]
            .joined(separator: "\n")
    }
}
