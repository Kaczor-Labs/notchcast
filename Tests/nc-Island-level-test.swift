// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandLevelDwell.swift
// notchcast-sources: Tinycast/Features/Island/Model/VolumeLevel+Island.swift
// notchcast-sources: Tinycast/Features/SystemActions/Model/VolumeLevel.swift
import Foundation

@main
struct IslandLevelTest {
    static func main() {
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
        precondition(zoned.fill == 25...87.5, "Fill runs from 0 into the upper zone: \(zoned.fill)")
        boosted.value = -0.25
        precondition(IslandLevelTrack(boosted, width: 100).fill == 12.5...25, "A negative value fills below 0")

        precondition(IslandLevelDwell.stacked(palette: true, question: false), "Palette means stacked")
        precondition(IslandLevelDwell.stacked(palette: false, question: true), "Question means stacked")
        precondition(!IslandLevelDwell.stacked(palette: false, question: false), "Neither means the pill")

        let muted = VolumeLevel.island(0.6, muted: true)
        let loud = VolumeLevel.island(0.6, muted: false)
        precondition(muted.source == "volume" && muted.symbol == "speaker.slash.fill" && muted.value == 0,
                     "Muted volume reads 0 with the slashed speaker")
        precondition(loud.symbol == "speaker.wave.2.fill" && abs(loud.value - 0.6) < 0.0001 && loud.label == "Volume")
        print("Island level: one presentation per burst, 1.5 s dwell, outlined zones and stacking under palette or question")
    }
}
