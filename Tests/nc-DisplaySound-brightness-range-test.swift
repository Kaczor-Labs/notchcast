// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/NotchcastMediaKey.swift
// notchcast-sources: Tinycast/Features/Notchcast/DisplaySound/Model/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandLevelDwell.swift
// notchcast-sources: Tinycast/Features/Notchcast/DisplaySound/Service/DisplaySoundSystem.swift
// notchcast-sources: Tinycast/Features/Notchcast/DisplaySound/Service/BrightnessDDCChannel.swift
// notchcast-sources: Tinycast/Features/Notchcast/DisplaySound/Service/BrightnessDisplayService.swift

import Synchronization

private let displayID = BrightnessDisplay.ID(rawValue: 1, uuid: "display")

private final class FakeBacklight: Sendable {
    static let baseline = BrightnessGamma(red: [0, 1], green: [0, 1], blue: [0, 1])

    struct State {
        var level = 1.0
        var gamma = FakeBacklight.baseline
    }

    let state = Mutex(State())
    let ticks: Double?

    init(ticks: Double?) { self.ticks = ticks }

    var output: (Double, Float) { state.withLock { ($0.level, $0.gamma.red.last!) } }

    var system: DisplaySoundSystem.Displays {
        .init(
            online: { [displayID.rawValue] },
            uuid: { _ in displayID.uuid },
            isActive: { _ in true },
            isBuiltIn: { _ in true },
            readSystem: { _ in self.state.withLock { $0.level } },
            writeSystem: { _, level in
                self.state.withLock { $0.level = self.ticks.map { (level * $0).rounded() / $0 } ?? level }
                return true
            },
            discoverDDC: { [:] },
            readGamma: { _ in self.state.withLock { $0.gamma } },
            writeGamma: { _, gamma in
                self.state.withLock { $0.gamma = gamma }
                return true
            })
    }
}

@main
enum BrightnessRangeTests {
    static func main() async {
        var failures: [String] = []
        for ticks in [nil, 125.0] as [Double?] {
            for extraDimming in [false, true] {
                let display = FakeBacklight(ticks: ticks)
                let service = BrightnessDisplayService(displays: display.system)
                _ = await service.perform(.refresh(names: [:]))
                _ = await service.perform(.extraDimming(extraDimming))
                let floor = extraDimming ? -BrightnessLevel.extraDimmingRange : 0
                for up in [false, true] {
                    let start = up ? floor : 1
                    let end = up ? 1 : floor
                    _ = await service.perform(.set(start, displayID))
                    var previous = BrightnessLevel(start, extraDimming: extraDimming)
                    var previousOutput = display.output
                    let context = "\(ticks == nil ? "exact" : "quantised"), extra dimming \(extraDimming), up \(up)"
                    for _ in 0..<24 where previous.value != end {
                        guard let snapshot = await service.perform(.step(up: up, fine: false, displayID)),
                              let level = snapshot.displays.first?.level else {
                            failures.append("\(context): step unavailable")
                            break
                        }
                        let output = display.output
                        guard up ? level.value > previous.value && output > previousOutput
                                 : level.value < previous.value && output < previousOutput else {
                            failures.append("\(context): stalled at \(previous.readout)")
                            break
                        }
                        previous = level
                        previousOutput = output
                    }
                    let endPicture = !up && extraDimming ? Float(BrightnessLevel.minimumPicture) : 1
                    if previous.value != end || previousOutput != (up ? 1 : 0, endPicture) {
                        failures.append("\(context): endpoint unreachable")
                    }
                }
            }
        }
        precondition(failures.isEmpty, failures.joined(separator: "\n"))
        print("brightness range with exact and quantised read-back: PASS")
    }
}
