// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/NotchcastCategory.swift
// notchcast-reads: Tinycast/Features/Launcher/UI/CompactBar.swift Tinycast/Features/Launcher/UI/SectionHeader.swift Tinycast/Features/Calculator/UI/CalculatorCardView.swift
// notchcast-reads: Tinycast/Features/AI/UI/ChatTranscriptView.swift Tinycast/Features/AI/UI/ChatSuggestionChips.swift
import Foundation

// design-system.md §13.8: island controls hang Tinycast's `.tooltip`, never the system `.help()`.
let islandFiles = [
    "Tinycast/Features/Launcher/UI/CompactBar.swift",
    "Tinycast/Features/Launcher/UI/SectionHeader.swift",
    "Tinycast/Features/Calculator/UI/CalculatorCardView.swift",
    "Tinycast/Features/AI/UI/ChatTranscriptView.swift",
    "Tinycast/Features/AI/UI/ChatSuggestionChips.swift",
]

func helpCalls(in source: String) -> [Int] {
    source.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
        .filter { $0.element.contains(".help(") }.map { $0.offset + 1 }
}

@main
enum NotchcastIslandTooltipsTests {
    static func main() throws {
        var failures: [String] = []

        if helpCalls(in: "Button {}\n    .buttonStyle(.plain)\n    .help(\"x\")\n") != [3] {
            failures.append("a planted .help( is not found")
        }
        if !helpCalls(in: "Button {}\n    .tooltip(\"x\")\n").isEmpty { failures.append("a .tooltip is flagged") }

        for path in islandFiles {
            let source = try String(contentsOfFile: path, encoding: .utf8)
            let hits = helpCalls(in: source)
            if !hits.isEmpty { failures.append("\(path):\(hits) uses .help(; use .tooltip(") }
            if !source.contains(".tooltip(") { failures.append("\(path) has no .tooltip(") }
        }

        failures.forEach { print("FAIL: \($0)") }
        if !failures.isEmpty { exit(1) }
        print("island tooltips ok")
    }
}
