import Foundation

/// How much of a walk's time budget the next Accessibility read may take.
nonisolated enum CopyPathBudget {
    /// AX rounds to whole milliseconds and reads 0 as its 6 s default, so a sliver ends the walk.
    static let minimumRead = Duration.milliseconds(10)

    /// The next read's timeout in seconds: `left`, at most `cap`; nil once too little is left.
    static func timeout(left: Duration, cap: Float) -> Float? {
        guard left >= minimumRead else { return nil }
        return min(cap, Float(left / .seconds(1)))
    }
}
