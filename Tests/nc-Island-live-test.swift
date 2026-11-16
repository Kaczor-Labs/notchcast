// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandLiveState.swift
import Foundation

@main
struct IslandLiveTest {
    static func main() {
        let download = IslandLiveState(update: .installing(text: "Downloading…", progress: 0.25))
        precondition(download.notice == IslandNotice(id: "update", symbol: "arrow.down.circle", text: "Downloading…",
                                                     progress: IslandProgress(fraction: 0.25, headline: false))
                     && download.noticeSeconds == nil && download.status == nil,
                     "Installing holds one compact progress notice until the stage changes, with no status")
        let expand = IslandLiveState(update: .installing(text: "Expanding…", progress: nil))
        precondition(expand.notice?.id == download.notice?.id
                     && expand.notice?.progress == IslandProgress(fraction: nil, headline: false)
                     && expand.notice?.isHeadline == false,
                     "Every install phase reposts the same compact notice; an unknown stage claims no fraction")

        let ready = IslandLiveState(update: .ready)
        precondition(ready.notice?.text == "Update ready" && ready.notice?.symbol == "arrow.clockwise.circle"
                     && ready.notice?.isFailure == false && ready.noticeSeconds == 2.4,
                     "Ready shows its notice for 2.4 s")
        precondition(ready.status == IslandStatus(id: "update", symbol: "arrow.clockwise.circle", label: "Update ready"),
                     "Ready leaves the update status behind its notice")

        let failed = IslandLiveState(update: .failed)
        precondition(failed.notice?.text == "Update failed" && failed.notice?.isFailure == true
                     && failed.noticeSeconds == 4, "Failed shows a failure notice for 4 s")
        precondition(failed.status?.id == "update" && failed.status?.symbol == "exclamationmark.arrow.circlepath"
                     && failed.status?.label == "Update failed", "Failed leaves the retry status")

        let cancelled = IslandLiveState(update: .none)
        precondition(cancelled.notice == nil && cancelled.status == nil && cancelled.noticeSeconds == nil,
                     "Cancel or an automatic offer ends the notice and clears the status")
        precondition(cancelled != ready && cancelled == IslandLiveState(update: .none), "Equal stages compare equal")

        let installed = IslandLiveState(report: .installed(version: "1.2.3"))
        precondition(installed.notice == IslandNotice(id: "update", symbol: "checkmark.circle", text: "Updated to 1.2.3")
                     && installed.noticeSeconds == 2.4 && installed.status == nil,
                     "An installed report shows the version for the stock HUD's 2.4 s, with no status")
        let notInstalled = IslandLiveState(report: .notInstalled)
        precondition(notInstalled.notice?.text == "Update failed" && notInstalled.notice?.isFailure == true
                     && notInstalled.notice?.id == "update" && notInstalled.noticeSeconds == 4
                     && notInstalled.status == nil,
                     "A version that did not install shows a 4 s failure notice and leaves no status")
        print("Island live: install, ready, failed, cancel and the launch report map to the update notice and status")
    }
}
