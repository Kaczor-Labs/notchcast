import Foundation

struct KeepAwakePolicy: Sendable, Equatable {
    enum Outcome: Sendable, Equatable { case off, expired, batteryFloor, hold }

    static let floorCap = 50

    var enabled = false
    var until: Date?
    var floor = KeepAwakeSettings.defaultFloor

    func evaluate(now: Date, onBattery: Bool, percent: Int?) -> Outcome {
        guard enabled else { return .off }
        if let until, now >= until { return .expired }
        if onBattery, floor > 0 {
            guard let percent, (0...100).contains(percent), percent > min(Self.floorCap, floor) else {
                return .batteryFloor
            }
        }
        return .hold
    }

    var assertionTypes: [String] {
        ["PreventUserIdleSystemSleep", "PreventUserIdleDisplaySleep"]
    }
}
