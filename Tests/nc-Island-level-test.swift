// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandLevelDwell.swift
// notchcast-sources: Tinycast/Features/Island/Model/VolumeLevel+Island.swift
// notchcast-sources: Tinycast/Features/SystemActions/Model/VolumeLevel.swift
import Foundation

@main
struct IslandLevelTest {
    static func main() {
        var reading = IslandLevel(source: "volume", symbol: "speaker.wave.2.fill", label: "Volume", value: 0.734)
        precondition(reading.readout == "73%", "a level reads as a whole percent, got \(reading.readout)")
        reading.value = 1
        precondition(reading.readout == "100%", "full reads 100%")
        reading.value = 0
        precondition(reading.readout == "0%", "empty or muted reads 0%")
        reading.value = 0.125
        precondition(reading.readout == "13%", "half a percent rounds away from zero, got \(reading.readout)")
        reading.value = 0.625
        precondition(reading.readout == "63%", "62.5% rounds away from zero, got \(reading.readout)")
        var dimmable = IslandLevel(source: "brightness", symbol: "sun.min.fill", label: "Brightness", value: -0.25,
                                   range: -0.25...1)
        precondition(dimmable.readout == "0%", "the darkest extra dimming reads 0%, got \(dimmable.readout)")
        dimmable.value = 0
        precondition(dimmable.readout == "20%", "the system minimum sits a fifth along, got \(dimmable.readout)")
        dimmable.value = 1
        precondition(dimmable.readout == "100%", "the brightest reads 100%, got \(dimmable.readout)")
        dimmable.value = 0.03125
        precondition(dimmable.readout == "23%", "22.5% rounds away from zero, got \(dimmable.readout)")
        dimmable.value = -1
        precondition(dimmable.readout == "0%", "a value past the bar clamps to 0%, got \(dimmable.readout)")
        var dwell = IslandLevelDwell()
        let level = IslandLevel(source: "brightness", symbol: "sun.max.fill", label: "Brightness", value: 0)
        var starts = 0
        var last = 0.0
        for call in 0..<60 {
            last = 100 + Double(call) * 2 / 60
            var next = level
            next.value = Double(call) / 59
            if dwell.show(next, at: last) { starts += 1 }
        }
        precondition(starts == 1 && dwell.presentation == 1, "60 calls in 2 s give one presentation, got \(starts)")
        let token = dwell.presentation
        precondition(dwell.remaining(token, at: last + 1.49) != nil, "Still showing 1.49 s after the last call")
        precondition(dwell.remaining(token, at: last + 1.5) == nil && dwell.level == nil,
                     "Gone 1.5 s after the last call")
        precondition(dwell.show(level, at: last + 2), "A call after the dwell starts a new presentation")
        precondition(dwell.remaining(token, at: last + 2) == nil, "A replaced presentation's token never applies")

        let plain = IslandLevelTrack(level, width: 100)
        precondition(plain.below == nil && plain.above == nil && plain.track == 0...100 && plain.fill == 0...0,
                     "0...1 has no zones")
        var boosted = level
        boosted.range = -0.5...1.5
        boosted.value = 1.25
        let zoned = IslandLevelTrack(boosted, width: 100)
        precondition(zoned.below == 0...25 && zoned.track == 25...75 && zoned.above == 75...100,
                     "Outside 0...1 draws outlined zones past the track: \(zoned)")
        precondition(zoned.fill == 0...87.5, "Fill runs from the left edge into the upper zone: \(zoned.fill)")
        boosted.value = -0.25
        precondition(IslandLevelTrack(boosted, width: 100).fill == 0...12.5, "A negative value fills from the left")
        var lit = IslandLevel(source: "brightness", symbol: "sun.max.fill", label: "Brightness", value: -0.25,
                              range: -0.25...1)
        for step in 0...80 {
            lit.value = -0.25 + Double(step) / 64
            let fill = IslandLevelTrack(lit, width: 100).fill
            let percent = Double(IslandLevel.percent(lit.value, in: lit.range))
            precondition(fill.lowerBound == 0 && abs(fill.upperBound - percent) <= 0.5 + 1e-9,
                         "The fill is the readout's share of the bar at \(lit.value): \(fill) vs \(percent)%")
        }
        lit.value = -0.25
        precondition(IslandLevelTrack(lit, width: 100).fill == 0...0, "The darkest reads 0% and shows no fill")
        lit.value = 0
        precondition(IslandLevelTrack(lit, width: 100).fill == 0...20, "The system minimum fills a fifth")
        lit.value = 1
        precondition(IslandLevelTrack(lit, width: 100).fill == 0...100, "The brightest fills the whole bar")

        var live = IslandLevelDwell()
        precondition(live.placement(palette: false, question: false) == nil, "Nothing live, nothing placed")
        _ = live.show(level, at: 10)
        let (start, deadline) = (live.presentation, live.deadline)
        precondition(live.placement(palette: false, question: false) == .pill, "Neither means the pill")
        precondition(live.placement(palette: true, question: false) == .band, "Palette opening mid-level means the band")
        precondition(live.placement(palette: false, question: true) == .band, "Question means the band")
        precondition(live.placement(palette: false, question: false) == .pill, "Closing them returns it to the pill")
        precondition(live.presentation == start && live.deadline == deadline, "A move keeps the token and deadline")
        precondition(!live.show(level, at: 11) && live.presentation == start, "Replacing a level keeps one presentation")
        precondition(live.placement(palette: true, question: false) == .band, "The replacement stays in the band")
        precondition(live.remaining(start, at: 12.5) == nil && live.level == nil, "Expiry ends the level")
        precondition(live.placement(palette: true, question: false) == nil
                     && live.placement(palette: false, question: false) == nil, "Expiry clears pill and band")

        let muted = VolumeLevel.island(0.6, muted: true)
        let loud = VolumeLevel.island(0.6, muted: false)
        precondition(muted.source == "volume" && muted.symbol == "speaker.slash.fill" && muted.value == 0,
                     "Muted volume reads 0 with the slashed speaker")
        precondition(loud.symbol == "speaker.wave.2.fill" && abs(loud.value - 0.6) < 0.0001 && loud.label == "Volume")
        print("Island level: one presentation per burst, 1.5 s dwell, outlined zones and pill/band placement")
    }
}
