// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandLiveState.swift
// notchcast-reads: Tinycast/Features/Updates/UI/UpdatePill.swift Tinycast/Features/Updates/UI/UpdateCoordinator.swift
import Foundation

/// Design system §9/§10: one glyph per update state in the notice, the status, the footer pill and the
/// Try Again dialog, and the footer pill carries no tint fill, tinted glass or spinner of its own.
@main
struct NotchcastUpdateGlyphTest {
    static func main() throws {
        let live = IslandLiveState.self
        let installing = IslandLiveState(update: .installing(text: "Downloading…", progress: nil))
        let ready = IslandLiveState(update: .ready)
        let failed = IslandLiveState(update: .failed)
        precondition(installing.notice?.symbol == live.installingSymbol, "the installing notice uses installingSymbol")
        precondition(ready.notice?.symbol == live.readySymbol && ready.status?.symbol == live.readySymbol,
                     "the ready notice and status use readySymbol")
        precondition(failed.notice?.symbol == live.failedSymbol && failed.status?.symbol == live.failedSymbol,
                     "the failed notice and status use failedSymbol")
        precondition(IslandLiveState(report: .notInstalled).notice?.symbol == live.failedSymbol,
                     "a version that did not install shows the failed glyph")
        precondition(Set([live.installingSymbol, live.readySymbol, live.failedSymbol]).count == 3,
                     "each update state has its own glyph")

        let pill = try String(contentsOfFile: "Tinycast/Features/Updates/UI/UpdatePill.swift", encoding: .utf8)
        for symbol in ["installingSymbol", "readySymbol", "failedSymbol"] {
            precondition(pill.contains("IslandLiveState.\(symbol)"), "the footer pill uses \(symbol)")
        }
        let coordinator = try String(
            contentsOfFile: "Tinycast/Features/Updates/UI/UpdateCoordinator.swift", encoding: .utf8)
        precondition(coordinator.contains("symbol: IslandLiveState.failedSymbol"),
                     "the Try Again dialog shows the failed state's glyph")
        for literal in ["checkmark.circle.fill", "exclamationmark.circle.fill", "progress.indicator", ".spinner",
                        ".tint(", "Opacity", "controlSurface", ".opacity(0."] {
            precondition(!pill.contains(literal), "the footer pill has no \(literal)")
        }
        precondition(pill.contains("Circle().stroke(Theme.Colors.border"), "the progress track is Theme.Colors.border")
        print("PASS the update flow shows one glyph per state and the footer pill keeps its tint on glyph, ring and label")
    }
}
