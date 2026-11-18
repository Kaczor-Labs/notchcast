import Foundation

/// A source that timed out or failed: the run reports Unavailable and never reads the next source.
nonisolated struct CopyPathUnavailable: Error, Equatable, Sendable {}

/// One raw read status: an answer (true), nothing there (false, the next source runs), or a throw.
nonisolated enum CopyPathStatus {
    static let appleEventNothingThere = [-1728, -1719, -1708]
    static let appleEventRefused = [-1743, -1744]
    static let axSuccess: Int32 = 0
    static let axNothingThere: [Int32] = [-25212, -25205]
    static let axDisabled: Int32 = -25211

    /// Missing object, bad index or unhandled verb are nothing there; -1712 and the rest stop the run.
    static func appleEvent(_ status: Int, denied: CopyPathFailure) throws -> Bool {
        if status == 0 { return true }
        if appleEventNothingThere.contains(status) { return false }
        if appleEventRefused.contains(status) { throw denied }
        throw CopyPathUnavailable()
    }

    /// No value or unsupported is nothing there; cannotComplete (the 1 s timeout) and the rest stop.
    static func accessibility(_ status: Int32) throws -> Bool {
        if status == axSuccess { return true }
        if axNothingThere.contains(status) { return false }
        if status == axDisabled { throw CopyPathFailure.accessibility }
        throw CopyPathUnavailable()
    }
}
