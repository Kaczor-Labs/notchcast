// notchcast-sources: Tinycast/Features/Island/Model/IslandPlayer.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
import Foundation

func check(_ condition: Bool, _ message: String) {
    guard condition else { fatalError("nc-Island-song-test: \(message)") }
}

@main
struct IslandSongTest {
    static func main() {
        line()
        marquee()
        equalizer()
        songChange()
        voiceOver()
        print("Island song: line widths, marquee, meter, song change and VoiceOver hold")
    }

    static let song = IslandNowPlaying(title: "Paper Lanterns", artist: "Juno Vale", artwork: nil, time: nil,
                                       isPlaying: true, id: "a")

    /// D15: widen keeps the whole line up to its cap; scroll keeps the cap and moves the line inside it.
    static func line() {
        let short = IslandSongLine(text: 120, cap: 228, overflow: .widen)
        check(short.width == 120 && !short.scrolls, "a short line fits and stays still")
        check(IslandSongLine(text: 120, cap: 228, overflow: .scroll) == short, "scroll changes nothing that fits")
        let long = IslandSongLine(text: 400, cap: 228, overflow: .scroll)
        check(long.width == 228 && long.scrolls, "a long line keeps the cap and scrolls")
        let cut = IslandSongLine(text: 700, cap: 588, overflow: .widen)
        check(cut.width == 588 && !cut.scrolls, "widen stops at its own cap and never scrolls")
    }

    static func marquee() {
        let offset = { IslandSongLine.offset(text: 300, gap: 28, speed: 30, pause: 1.5, at: $0) }
        check(offset(0) == 0 && offset(1.4) == 0, "the line rests at the start first")
        check(abs(offset(2.5) - 30) < 0.001, "then moves at its speed")
        let cycle = 1.5 + 328.0 / 30
        check(offset(cycle) == 0 && offset(cycle + 1) == 0, "the copy behind it brings it round to the start")
        check(IslandSongLine.offset(text: 0, gap: 0, speed: 30, pause: 1, at: 5) == 0, "nothing to move")
    }

    /// D24: the fake meter stays in its cell, moves while playing and rests while paused.
    static func equalizer() {
        var seen = Set<[Int]>()
        for step in 0..<200 {
            let levels = IslandEqualizer.levels(at: Double(step) / 30, playing: true)
            check(levels.count == IslandEqualizer.bars, "one level per bar")
            check(levels.allSatisfy { $0 >= IslandEqualizer.floor - 1e-9 && $0 <= 1 + 1e-9 }, "inside the cell")
            seen.insert(levels.map { Int($0 * 10) })
        }
        check(seen.count > 50, "the bars keep moving rather than looping a few frames")
        check(Set(IslandEqualizer.levels(at: 1, playing: true).map { Int($0 * 100) }).count > 1, "bars differ")
        check(IslandEqualizer.levels(at: 7, playing: false).allSatisfy { $0 == IslandEqualizer.floor }, "paused rests")
    }

    /// D16: below a notch only, once per new song, never for the first song seen.
    static func songChange() {
        var change = IslandSongChange(seconds: 2.4)
        check(!change.update(song, notch: true, at: 0), "the first song only arms it")
        check(!change.update(song, notch: true, at: 1), "the same song again is no change")
        var paused = song
        paused.isPlaying = false
        check(!change.update(paused, notch: true, at: 1.5), "pausing is no change")
        var next = song
        next.id = "b"
        check(change.update(next, notch: true, at: 2), "a new song on a notch shows")
        check(change.shown == "b" && abs((change.remaining(at: 3) ?? 0) - 1.4) < 1e-9, "for one message dwell")
        change.expire(at: 3)
        check(change.shown == "b", "not before its dwell")
        change.expire(at: 4.4)
        check(change.shown == nil && change.remaining(at: 5) == nil, "gone after it")
        next.id = "c"
        check(!change.update(next, notch: false, at: 5), "never without a notch: the pill already names it")
        next.id = "d"
        check(change.update(next, notch: true, at: 6), "a notch again shows the next one")
        change.cut()
        check(change.shown == nil, "a level, notice, meeting or the open island cuts it")
        check(!change.update(nil, notch: true, at: 7) && change.shown == nil, "clearing shows nothing")
        next.id = "e"
        check(change.update(next, notch: true, at: 8), "a song after a clear is a change")
        var named = IslandNowPlaying(title: "One", artist: "A", artwork: nil, time: nil, isPlaying: true)
        var byName = IslandSongChange()
        _ = byName.update(named, notch: true, at: 0)
        named.title = "Two"
        check(byName.update(named, notch: true, at: 1), "without an id the names tell songs apart")
    }

    static func voiceOver() {
        check(song.accessibilityValue == "Paper Lanterns, Juno Vale, Playing", "full names and state")
        var paused = song
        paused.isPlaying = false
        paused.artist = nil
        check(paused.accessibilityValue == "Paper Lanterns, Paused", "no empty part")
    }
}
