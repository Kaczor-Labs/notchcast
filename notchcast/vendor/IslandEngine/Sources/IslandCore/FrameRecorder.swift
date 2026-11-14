import Foundation

/// Frame timing while the island animated: the wall-clock gap between frames and each frame's work.
public struct FrameStats: Sendable, Equatable {
    /// Mean, 95th percentile and maximum of a run of timings, in ms, each to two decimals.
    public struct Summary: Sendable, Equatable {
        public var mean: Double
        public var p95: Double
        public var max: Double

        public init(mean: Double, p95: Double, max: Double) {
            self.mean = mean
            self.p95 = p95
            self.max = max
        }
    }

    /// Frames recorded.
    public var frames: Int
    /// Gaps between consecutive animating frames, in ms.
    public var interval: Summary
    /// Time the island's own per-frame work took, in ms.
    public var work: Summary
    /// Frames whose gap exceeded 1.5x the 60 fps budget (25 ms).
    public var longFrames: Int

    public init(frames: Int, interval: Summary, work: Summary, longFrames: Int) {
        self.frames = frames
        self.interval = interval
        self.work = work
        self.longFrames = longFrames
    }
}

/// Records each animating frame's start and work, keeping the last `limit` of each.
@MainActor
public final class FrameRecorder {
    private let limit: Int
    private var intervals: [Double] = []
    private var work: [Double] = []
    private var last: Double?

    public init(limit: Int = 2000) {
        self.limit = limit
    }

    /// Records one frame: when it started (wall ms) and how long the island's work took (ms).
    public func record(startedAt: Double, work cost: Double) {
        if let last { intervals.append(startedAt - last) }
        last = startedAt
        work.append(cost)
        if work.count > limit {
            work = sliceLast(work, limit)
            intervals = sliceLast(intervals, limit)
        }
    }

    /// `array.slice(-count)`: a count of 0 is `slice(-0)`, which keeps everything.
    private func sliceLast(_ array: [Double], _ count: Int) -> [Double] {
        let start = count > 0 ? max(array.count - count, 0) : min(-count, array.count)
        return Array(array[start...])
    }

    /// Marks a gap (the island went to rest), so idle time isn't counted as a long frame.
    public func breakRun() {
        last = nil
    }

    /// The timings recorded since the last `clear`.
    public var stats: FrameStats {
        FrameStats(
            frames: work.count, interval: summarize(intervals), work: summarize(work),
            longFrames: intervals.filter { $0 > 25 }.count)
    }

    public func clear() {
        intervals = []
        work = []
        last = nil
    }
}

private func summarize(_ values: [Double]) -> FrameStats.Summary {
    guard !values.isEmpty else { return FrameStats.Summary(mean: 0, p95: 0, max: 0) }
    var sorted = values
    jsSort(&sorted) { $0 - $1 }
    let mean = values.reduce(0, +) / Double(values.count)
    let p95 = sorted[min(sorted.count - 1, Int((Double(sorted.count) * 0.95).rounded(.down)))]
    return FrameStats.Summary(mean: jsRound2(mean), p95: jsRound2(p95), max: jsRound2(sorted[sorted.count - 1]))
}

/// `Math.round(n * 100) / 100`.
private func jsRound2(_ value: Double) -> Double {
    jsRound(value * 100) / 100
}
