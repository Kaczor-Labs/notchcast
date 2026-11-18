// notchcast-sources: -module-name NotchcastFooterMenuHidden
// notchcast-reads: Tinycast/Palette/RootPaletteView.swift
import Foundation

/// #882: the launcher footer shows no round app-menu button, so nothing opens its menu.
@main
struct NotchcastFooterMenuHiddenTest {
    static func main() throws {
        let source = try String(contentsOfFile: "Tinycast/Palette/RootPaletteView.swift", encoding: .utf8)
        let raw = source.components(separatedBy: "\n")
        let lines = raw.map { $0.trimmingCharacters(in: .whitespaces) }
        guard let start = lines.firstIndex(of: "private var appMenuButton: some View {"),
              case let indent = raw[start].prefix(while: { $0 == " " }),
              let end = raw[start...].firstIndex(of: indent + "}") else {
            preconditionFailure("RootPaletteView declares appMenuButton; re-check #882 if upstream renamed it")
        }
        let body = lines[(start + 1)..<end]
        precondition(body.last == ".notchcastHidden()", "the footer's app-menu button ends in .notchcastHidden()")
        let circles = lines.indices.filter { lines[$0].hasPrefix("MenuCircleButton") }
        precondition(circles.allSatisfy { body.indices.contains($0) },
                     "MenuCircleButton is built only inside the hidden appMenuButton")
        let openers = lines.indices.filter { lines[$0].contains("open(.app") }
        precondition(!openers.isEmpty && openers.allSatisfy { body.indices.contains($0) },
                     "only the hidden button opens the app menu")
        print("PASS the launcher footer has no app-menu button and nothing else opens its menu")
    }
}
