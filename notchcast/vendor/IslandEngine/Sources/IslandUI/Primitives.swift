import IslandCore
import Observation
import SwiftUI

/// The clock and reduced-motion setting a primitive runs on: the nearest model's, else the shared one.
@MainActor
private struct PrimitiveClock {
    var clock: any IslandClock
    var reduced: Bool

    init(_ environment: EnvironmentValues) {
        clock = environment.islandClock
        reduced = environment.islandReducedMotion
    }
}

/// Text whose changed characters turn over with a blur, like a Live Activity's numeric text
/// transition. Unchanged characters stay put; places align from the right, so 9 to 10 turns both.
/// A value that changes again mid-turn crossfades quickly from where the turn is.
public struct IslandNumber: View {
    @Environment(\.self) private var environment
    @Environment(\.font) private var font
    @Environment(\.fontResolutionContext) private var fontContext
    @State private var driver = NumberDriver()

    let text: String
    let turn: Double?

    /// - Parameter turn: Seconds a changed character takes to turn over; nil keeps the measured 0.48 s.
    public init(_ value: String, turn: Double? = nil) {
        text = value
        self.turn = turn
    }

    /// A number as JavaScript's `String(value)` writes it.
    public init(_ value: Double, turn: Double? = nil) {
        self.init(jsString(value), turn: turn)
    }

    public init(_ value: Int, turn: Double? = nil) {
        self.init(String(value), turn: turn)
    }

    public var body: some View {
        let clock = PrimitiveClock(environment)
        let em = (font ?? .body).resolve(in: fontContext).pointSize
        let setup = NumberDriver.Setup(em: em, reduced: clock.reduced, turn: turn)
        // The island measures slots in a layout of their own, which may not run `onChange` first.
        let places = driver.places.isEmpty ? NumberTurn(text).places(at: 0) : driver.places
        HStack(spacing: 0) {
            ForEach(numberRuns(places), id: \.index) { _, place in
                switch place {
                case .plain(let character):
                    Text(character)
                case .cell(let incoming, let outgoing):
                    ZStack {
                        glyph(incoming)
                        ForEach(outgoing.indices, id: \.self) { glyph(outgoing[$0]) }
                    }
                }
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .onChange(of: setup, initial: true) { _, setup in
            driver.configure(setup, text: text, clock: clock.clock)
        }
        .onChange(of: text.islandIdentity) {
            driver.show(text, clock: clock.clock)
        }
        .onChange(of: ObjectIdentifier(clock.clock)) {
            driver.follow(clock.clock)
        }
    }

    /// Blur first, then the transform, as CSS applies `filter` before `transform`.
    private func glyph(_ glyph: NumberGlyph) -> some View {
        Text(glyph.character)
            .blur(radius: glyph.blur > 0 ? glyph.blur * blurScale : 0)
            .scaleEffect(glyph.scale)
            .offset(y: glyph.offsetY)
            .opacity(glyph.opacity)
    }
}

private func numberRuns(_ places: [NumberPlace]) -> [(index: Int, place: NumberPlace)] {
    var runs: [(index: Int, place: NumberPlace)] = []
    for (index, place) in places.enumerated() {
        if case .plain(let text) = place, let last = runs.last, case .plain(let prefix) = last.place {
            // Adjacent DOM text nodes shape together; only a turning cell breaks the run.
            runs[runs.count - 1].place = .plain(prefix + text)
        } else {
            runs.append((index, place))
        }
    }
    return runs
}

/// Holds an `IslandNumber`'s turn and draws its frames on the clock until it rests.
@MainActor
@Observable
final class NumberDriver {
    struct Setup: Equatable {
        var em: Double
        var reduced: Bool
        var turn: Double?
    }

    private(set) var places: [NumberPlace] = []
    @ObservationIgnored private var turn: NumberTurn?
    @ObservationIgnored private var setup: Setup?
    @ObservationIgnored private var stop: Cancel?

    func configure(_ setup: Setup, text: String, clock: any IslandClock) {
        guard setup != self.setup else { return }
        self.setup = setup
        stop?()
        stop = nil
        if turn == nil {
            turn = NumberTurn(text, turn: setup.turn, fontSize: setup.em, reducedMotion: setup.reduced)
        } else {
            turn?.reconfigure(turn: setup.turn, fontSize: setup.em, reducedMotion: setup.reduced)
        }
        if !draw(at: clock.now()) { run(on: clock) }
    }

    func show(_ text: String, clock: any IslandClock) {
        guard turn != nil else { return }
        let now = clock.now()
        turn?.set(text, at: now)
        if draw(at: now) {
            stop?()
            stop = nil
            return
        }
        if stop != nil { return }
        run(on: clock)
    }

    /// Moves the turn in flight to another clock, as upstream's effect restarts on its clock.
    func follow(_ clock: any IslandClock) {
        stop?()
        stop = nil
        if let setup {
            turn?.reconfigure(turn: setup.turn, fontSize: setup.em, reducedMotion: setup.reduced, clockChanged: true)
        }
        if turn == nil || draw(at: clock.now()) { return }
        run(on: clock)
    }

    private func run(on clock: any IslandClock) {
        stop = clock.onFrame { [weak self] now in
            guard let self, self.draw(at: now) else { return }
            self.stop?()
            self.stop = nil
        }
    }

    /// Draws the frame at `ms`; true once every place has finished turning.
    @discardableResult
    private func draw(at ms: Double) -> Bool {
        guard let turn else { return true }
        let next = turn.places(at: ms)
        places = next.enumerated().map { index, place in
            guard case .cell(let incoming, let outgoing) = place else { return place }
            var previousIn: NumberGlyph?
            var previousOut: [NumberGlyph] = []
            if index < places.count, case .cell(let oldIn, let oldOut) = places[index] {
                previousIn = oldIn
                previousOut = oldOut
            }
            // Browsers reject NaN opacity and transforms, keeping the last valid style.
            func painted(_ glyph: NumberGlyph, previous: NumberGlyph?, opacity: Double) -> NumberGlyph {
                var result = glyph
                if !glyph.opacity.isFinite { result.opacity = previous?.opacity ?? opacity }
                if !glyph.scale.isFinite || !glyph.offsetY.isFinite {
                    result.scale = previous?.scale ?? 1
                    result.offsetY = previous?.offsetY ?? 0
                }
                return result
            }
            return .cell(incoming: painted(incoming, previous: previousIn, opacity: 0),
                outgoing: outgoing.enumerated().map { k, glyph in
                    painted(glyph, previous: k < previousOut.count ? previousOut[k] : nil, opacity: 1)
                })
        }
        return turn.isAtRest(at: ms)
    }

    isolated deinit {
        stop?()
    }
}

/// A capsule progress bar whose fill eases to each new value, as a Live Activity's does.
public struct IslandProgress: View {
    /// How the fill moves when no spring is given.
    public static let defaultSpring = ProgressFill.defaultSpring

    @Environment(\.self) private var environment
    @State private var driver = ProgressDriver()

    let value: Double
    let color: Color
    let track: Color
    let height: Double
    let radius: Double?
    let spring: SpringConfig

    /// - Parameters:
    ///   - value: Fill from 0 to 1. Changes ease to the new value.
    ///   - radius: Corner radius; nil is half the height, a capsule.
    public init(
        value: Double, color: Color = Color(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255),
        track: Color = Color(red: 0x41 / 255, green: 0x41 / 255, blue: 0x41 / 255), height: Double = 8,
        radius: Double? = nil, spring: SpringConfig = IslandProgress.defaultSpring
    ) {
        self.value = value
        self.color = color
        self.track = track
        self.height = height
        self.radius = radius
        self.spring = spring
    }

    public var body: some View {
        let clock = PrimitiveClock(environment)
        let r = radius ?? height / 2
        let setup = ProgressDriver.Setup(reduced: clock.reduced, spring: spring)
        RoundedRectangle(cornerRadius: r, style: .circular)
            .fill(track)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: r, style: .circular)
                        .fill(color)
                        .frame(width: proxy.size.width * driver.width)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: r, style: .circular))
            .accessibilityElement(children: .ignore)
            .accessibilityRepresentation {
                ProgressView(value: driver.target)
            }
            .accessibilityValue("\(Int(driver.percent))%")
            .onChange(of: setup, initial: true) { _, setup in
                driver.configure(setup, value: value, clock: clock.clock)
            }
            .onChange(of: value) { _, value in
                driver.show(value, clock: clock.clock)
            }
            .onChange(of: ObjectIdentifier(clock.clock)) {
                driver.follow(clock.clock)
            }
    }
}

/// Holds an `IslandProgress`'s fill and draws its frames on the clock until it rests.
@MainActor
@Observable
final class ProgressDriver {
    struct Setup: Equatable {
        var reduced: Bool
        var spring: SpringConfig
    }

    /// The fill's share of the track, as the `toFixed(3)` percentage upstream writes.
    private(set) var width = 0.0
    private(set) var target = 0.0
    private(set) var percent = 0.0
    @ObservationIgnored private var fill: ProgressFill?
    @ObservationIgnored private var setup: Setup?
    @ObservationIgnored private var stop: Cancel?

    func configure(_ setup: Setup, value: Double, clock: any IslandClock) {
        guard setup != self.setup else { return }
        self.setup = setup
        let now = clock.now()
        if fill == nil {
            fill = ProgressFill(value: value, at: now, spring: setup.spring, reducedMotion: setup.reduced)
        } else {
            fill?.reconfigure(spring: setup.spring, reducedMotion: setup.reduced, at: now)
        }
        show(value, clock: clock)
    }

    func show(_ value: Double, clock: any IslandClock) {
        let now = clock.now()
        fill?.set(value, at: now)
        draw()
        if stop == nil { run(on: clock) }
    }

    /// Heads for the same target again from another clock's now, as upstream's effect does when its clock changes.
    func follow(_ clock: any IslandClock) {
        stop?()
        stop = nil
        fill?.restart(at: clock.now())
        draw()
        run(on: clock)
    }

    private func run(on clock: any IslandClock) {
        guard fill?.isRunning == true else { return }
        stop = clock.onFrame { [weak self] now in
            guard let self else { return }
            self.fill?.frame(at: now)
            self.draw()
            if self.fill?.isRunning != true {
                self.stop?()
                self.stop = nil
            }
        }
    }

    private func draw() {
        guard let fill else { return }
        width = (fill.painted * 100_000).rounded() / 100_000
        target = fill.target
        percent = fill.percent
    }

    isolated deinit {
        stop?()
    }
}

