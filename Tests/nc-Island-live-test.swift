// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandLiveState.swift
import Foundation

@main
struct IslandLiveTest {
    static func main() {
        let download = IslandLiveState(update: .installing(text: "Downloading…", progress: 0.25))
        precondition(download.notice == IslandNotice(id: "update", symbol: "arrow.down.circle", text: "Downloading…",
                                                     progress: 0.25)
                     && download.noticeSeconds == nil && download.status == nil,
                     "Installing holds one progress notice until the stage changes, with no status")
        let verify = IslandLiveState(update: .installing(text: "Verifying…", progress: 1))
        precondition(verify.notice?.id == download.notice?.id && verify.notice?.progress == 1,
                     "Every install phase reposts the same notice id")

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
        print("Island live: install, ready, failed and cancel map to the update notice and status")
    }
}
