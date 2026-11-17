import Foundation

/// One monitor's DDC/CI luminance control, classified by whether it answers.
struct BrightnessDDCChannel: Sendable {
    let link: BrightnessDDCLink
    private(set) var maximum: UInt16?

    mutating func probe() -> BrightnessRecoveryPolicy.ChannelOutcome {
        var accepted = false
        for _ in 0..<3 {
            guard !Task.isCancelled else { break }
            guard link.send(BrightnessDDC.request()) else { continue }
            accepted = true
            if let reply = link.receive(BrightnessDDC.replyLength).flatMap(BrightnessDDC.parse) {
                maximum = reply.maximum
                return .live(current: reply.current, maximum: reply.maximum)
            }
        }
        return BrightnessRecoveryPolicy.channelOutcome(writeAccepted: accepted, reply: nil)
    }

    func write(_ level: Double) -> Bool {
        guard !Task.isCancelled else { return false }
        let value = BrightnessDDC.deviceValue(level, maximum: maximum ?? BrightnessDDC.assumedMaximum)
        return link.send(BrightnessDDC.write(value))
    }
}
