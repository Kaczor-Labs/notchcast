import Foundation

extension ContentStage {
    /// Carries what each layer drew before a key change into its new look, resolving to nothing.
    mutating func carryOver(_ before: [StringMap<LayerDraw>]?, changedAt: Double, mode: MotionMode, timing: ContentMotion) {
        if mode != .spring {
            carries = [:]
            capHolds = [:]
            return
        }
        guard let before else { return }
        let (shownAt, shownEarlier, shownEarliest) = (before[0], before[1], before[2])
        let current = scene?.key
        for (key, was) in shownAt {
            if !was.shown {
                capHolds[key] = nil
            } else if sameString(key, current) {
                capHolds[key] = .some(was.capTravel)
            } else if let travel = was.capTravel {
                capHolds[key] = .some(travel)
            } else {
                capHolds[key] = nil
            }
        }
        let after = sample(changedAt, carried: false)
        let later = sample(changedAt + speedStep * 1000, carried: false)
        let latest = sample(changedAt + 2 * speedStep * 1000, carried: false)
        let carryResponseMin = motion.content.carryResponseMin
        for (key, now) in after {
            let was = shownAt[key]
            let response = sameString(key, current) ? timing.enter.response : timing.exit.response
            var slotCarries: [SlotName: SlotCarry] = [:]
            if let was, was.shown, response > 0 {
                for (name, drawnNow) in now.slots {
                    guard let drawnBefore = was.slots[name],
                        drawnBefore.opacity > 0.001 || drawnNow.opacity > 0.001,
                        let delta = carryOf(drawnBefore, drawnNow)
                    else { continue }
                    let ratio = !sameString(key, current) && drawnBefore.opacity > 0.001 && drawnBefore.opacity < drawnNow.opacity
                        ? drawnBefore.opacity / drawnNow.opacity : nil
                    var speed: SlotDraw?
                    if let earlier = shownEarlier[key]?.slots[name], let earliest = shownEarliest[key]?.slots[name],
                        let next = later[key]?.slots[name], let last = latest[key]?.slots[name]
                    {
                        let came = speedOf(drawnBefore, earlier, earliest, sign: 1)
                        let goes = speedOf(drawnNow, next, last, sign: -1)
                        var out = came
                        for field in SlotDraw.fields {
                            out[keyPath: field] = field == \SlotDraw.cap && (drawnBefore.cap == 0 || drawnNow.cap == 0)
                                ? 0 : came[keyPath: field] - goes[keyPath: field]
                        }
                        if let ratio { out.opacity = (came.opacity - goes.opacity * ratio) / drawnNow.opacity }
                        speed = out
                    }
                    slotCarries[name] = SlotCarry(delta: delta, speed: speed, ratio: ratio)
                }
            } else if let was, !was.shown, now.shown, response > 0 {
                for (name, drawnNow) in now.slots where drawnNow.opacity > 0.001 {
                    var hidden = drawnNow
                    hidden.opacity = 0
                    if let delta = carryOf(hidden, drawnNow) {
                        slotCarries[name] = SlotCarry(delta: delta, speed: nil, ratio: nil)
                    }
                }
            }
            if slotCarries.isEmpty {
                carries[key] = nil
                continue
            }
            let resolve = max(response, carryResponseMin)
            var weight = AnimatedValue(1, precision: 1e-4)
            weight.set(
                0, at: changedAt / 1000, .spring(SpringConfig(response: resolve, dampingFraction: carryDamping)))
            carries[key] = Carry(weight: weight, at: changedAt / 1000, omega: 2 * .pi / resolve, slots: slotCarries)
        }
    }
}
