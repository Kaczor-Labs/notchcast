import Foundation

/// What devtools can play: named sequences, listed in `Object.keys` order.
public struct DevtoolsOptions<Content> {
    /// Named sequences `play` can run.
    public var sequences: KeyValuePairs<String, IslandSequence<Content>>

    public init(sequences: KeyValuePairs<String, IslandSequence<Content>> = [:]) {
        self.sequences = sequences
    }
}

/// `play` was given a name no sequence has.
public struct UnknownSequence: Error, Equatable, CustomStringConvertible {
    public var name: String
    public var known: [String]

    public var description: String {
        "islandcn: no sequence named \"\(name)\". Known: \(known.joined(separator: ", "))"
    }
}

/// Frame-exact control of an island's time: pause, step, seek, sequences and frame stats.
@MainActor
public final class IslandDevtools<Content> {
    private let clock: FrameClock
    private let store: IslandStore<Content>
    private let recorder: FrameRecorder
    private let named: [(name: String, sequence: IslandSequence<Content>)]
    private var loaded: (name: String, cancels: [Cancel])?

    public init(
        clock: FrameClock, store: IslandStore<Content>, recorder: FrameRecorder, options: DevtoolsOptions<Content>
    ) {
        self.clock = clock
        self.store = store
        self.recorder = recorder
        // `Object.keys` lists array-index keys first, ascending, then the rest in insertion order.
        var positions: StringMap<Int> = [:]
        var pairs: [(name: String, sequence: IslandSequence<Content>)] = []
        for (name, sequence) in options.sequences {
            if let index = positions[name] {
                pairs[index].sequence = sequence
            } else {
                positions[name] = pairs.count
                pairs.append((name, sequence))
            }
        }
        named = pairs.compactMap { pair in arrayIndex(pair.name).map { ($0, pair) } }.sorted { $0.0 < $1.0 }.map(\.1)
            + pairs.filter { arrayIndex($0.name) == nil }
    }

    /// Freezes island time.
    public func pause() {
        clock.pause()
    }

    public func resume() {
        clock.resume()
    }

    /// Advances paused time by `ms` and draws that frame. Returns the new time.
    @discardableResult
    public func step(_ ms: Double) -> Double {
        clock.step(ms)
        return clock.now()
    }

    /// Jumps to `ms`. With a sequence loaded, replays it from the start so the frame is exact.
    @discardableResult
    public func seek(_ ms: Double) -> Double {
        if let loaded {
            _ = try? load(loaded.name, paused: true)
            clock.step(ms)
        } else {
            clock.setTime(ms)
        }
        return clock.now()
    }

    /// Resets the island to the sequence's start at time 0 and runs it; `paused` waits for `step`.
    /// Returns the sequence's duration in ms.
    @discardableResult
    public func play(_ name: String, paused: Bool = false) throws -> Double {
        try load(name, paused: paused).duration
    }

    public func now() -> Double {
        clock.now()
    }

    /// Playback speed while running; 1 is real time.
    public func setTimeScale(_ scale: Double) {
        clock.timeScale = scale
    }

    /// The names `play` knows.
    public var sequences: [String] { named.map(\.name) }

    /// What the island shows right now.
    public func presentation() -> PresentationKind {
        store.presentation
    }

    /// Frame timings recorded while the island animated.
    public func stats() -> FrameStats {
        recorder.stats
    }

    public func clearStats() {
        recorder.clear()
    }

    private func load(_ name: String, paused: Bool) throws -> IslandSequence<Content> {
        guard let sequence = named.first(where: { sameString($0.name, name) })?.sequence else {
            throw UnknownSequence(name: name, known: sequences)
        }
        for cancel in loaded?.cancels ?? [] { cancel() }
        clock.pause()
        clock.setTime(0)
        let store = store
        store.batch { store.reset() }
        store.batch { store.instantly { sequence.setup?(store) } }
        // Each event renders as one change, as upstream flushes each timer on its own.
        let cancels = sequence.events.map { event in
            // Weak: the store holds the clock, so a strong capture would keep both alive for good.
            clock.at(event.at) { [weak store] _ in
                guard let store else { return }
                store.batch { event.run(store) }
            }
        }
        loaded = (name, cancels)
        recorder.clear()
        if !paused { clock.resume() }
        return sequence
    }
}

/// The index a key names when JavaScript treats it as an array index: canonical decimal below 2^32 - 1.
private func arrayIndex(_ key: String) -> UInt32? {
    guard let index = UInt32(key), index != .max, String(index) == key else { return nil }
    return index
}
