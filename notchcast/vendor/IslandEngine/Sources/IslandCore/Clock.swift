import Foundation

public typealias Cancel = @MainActor () -> Void

/// Island time, in milliseconds. Everything that moves reads the time from a clock instead of the
/// wall clock, so a capture can pause it and step exact frames. A clock also runs timers
/// (long-press, alert hold) so they fire at the same instant on every run.
@MainActor
public protocol IslandClock: AnyObject {
    func now() -> Double
    /// Calls `onFrame` once per frame until the returned closure is called.
    @discardableResult
    func onFrame(_ onFrame: @escaping @MainActor (Double) -> Void) -> Cancel
    /// Runs `run` once the clock reaches `at`, passing the time it was due.
    @discardableResult
    func at(_ at: Double, run: @escaping @MainActor (Double) -> Void) -> Cancel
}

/// Where a running clock gets its frames from: the display's refresh.
@MainActor
public protocol FrameSource: AnyObject {
    /// Calls `frame` once on the next refresh, and returns a token that cancels it.
    func requestFrame(_ frame: @escaping @MainActor () -> Void) -> Int
    func cancelFrame(_ token: Int)
}

/// The real clock, which can also be paused, stepped and sought for captures and tests.
/// Without a frame source it only moves when stepped.
@MainActor
public final class FrameClock: IslandClock {
    private struct Timer {
        var id: Int
        var at: Double
        var run: @MainActor (Double) -> Void
    }

    private var frameListeners: [(id: Int, onFrame: @MainActor (Double) -> Void)] = []
    private var timers: [Timer] = []
    private var nextID = 1
    private var pendingFrame: Int?
    private var frozenAt = 0.0
    // Island time = (wall time - origin) * scale + base, rebased when the scale or pause state changes.
    private var base = 0.0
    private var origin = 0.0
    private var scale = 1.0
    private let wall: @MainActor () -> Double
    private let frameSource: FrameSource?

    public private(set) var paused = false

    public init(
        frameSource: FrameSource? = nil,
        wall: @escaping @MainActor () -> Double = { ProcessInfo.processInfo.systemUptime * 1000 }
    ) {
        self.frameSource = frameSource
        self.wall = wall
    }

    public func now() -> Double {
        paused ? frozenAt : (wall() - origin) * scale + base
    }

    @discardableResult
    public func onFrame(_ onFrame: @escaping @MainActor (Double) -> Void) -> Cancel {
        let id = nextID
        nextID += 1
        frameListeners.append((id, onFrame))
        schedule()
        return { [weak self] in self?.frameListeners.removeAll { $0.id == id } }
    }

    @discardableResult
    public func at(_ at: Double, run: @escaping @MainActor (Double) -> Void) -> Cancel {
        let id = nextID
        nextID += 1
        timers.append(Timer(id: id, at: at, run: run))
        schedule()
        return { [weak self] in self?.timers.removeAll { $0.id == id } }
    }

    public func pause() {
        if paused { return }
        frozenAt = now()
        paused = true
        if let pendingFrame { frameSource?.cancelFrame(pendingFrame) }
        pendingFrame = nil
    }

    public func resume() {
        if !paused { return }
        base = frozenAt
        origin = wall()
        paused = false
        schedule()
    }

    /// Advances paused time by `ms`, firing due timers at their exact times, then draws one frame.
    public func step(_ ms: Double) {
        if !paused {
            frozenAt = now()
            paused = true
        }
        let target = frozenAt + ms
        runTimers(until: target) { frozenAt = $0 }
        frozenAt = target
        emitFrame(target)
    }

    /// Jumps to `ms` without firing the timers in between. Timers before `ms` fire on the next frame.
    public func setTime(_ ms: Double) {
        if paused {
            frozenAt = ms
        } else {
            base = ms
            origin = wall()
        }
        schedule()
    }

    /// Playback speed while running. 0.25 plays at quarter speed.
    public var timeScale: Double {
        get { scale }
        set {
            base = now()
            origin = wall()
            scale = newValue
        }
    }

    private func runTimers(until time: Double, setNow: (Double) -> Void) {
        while let due = timers.filter({ $0.at <= time }).min(by: { ($0.at, $0.id) < ($1.at, $1.id) }) {
            timers.removeAll { $0.id == due.id }
            setNow(due.at)
            due.run(due.at)
        }
    }

    private func emitFrame(_ time: Double) {
        for listener in frameListeners { listener.onFrame(time) }
    }

    private func loop() {
        pendingFrame = nil
        if paused { return }
        let time = now()
        runTimers(until: time) { _ in }
        emitFrame(time)
        schedule()
    }

    private func schedule() {
        guard pendingFrame == nil, !paused, let frameSource else { return }
        if frameListeners.isEmpty, timers.isEmpty { return }
        pendingFrame = frameSource.requestFrame { [weak self] in self?.loop() }
    }
}
