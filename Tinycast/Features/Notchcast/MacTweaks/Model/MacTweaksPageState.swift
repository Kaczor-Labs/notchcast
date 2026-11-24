import Foundation

struct MacTweaksPageState {
    enum Failure { case read, change }

    private(set) var snapshot: MacTweakSnapshot?
    private(set) var notice: String?

    mutating func clearNotice() { notice = nil }

    /// A busy or corrupt-journal reply carries no snapshot, so the last one stays on screen.
    mutating func received(_ snapshot: MacTweakSnapshot?, notice: String?) {
        if let snapshot { self.snapshot = snapshot }
        self.notice = notice
    }

    mutating func failed(_ failure: Failure) {
        snapshot = nil
        switch failure {
        case .read:
            notice = String(localized: "Couldn’t read Mac Tweaks. Refresh to try again.", table: "NotchcastMacTweaks")
        case .change:
            notice = String(
                localized: "Couldn’t finish the change. Refresh to check your settings.", table: "NotchcastMacTweaks")
        }
    }
}
