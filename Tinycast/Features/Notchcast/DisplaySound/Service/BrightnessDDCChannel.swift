import Foundation

/// One monitor's DDC/CI luminance control, classified by whether it answers.
struct BrightnessDDCChannel: Sendable {
    let link: BrightnessDDCLink
    private(set) var maximum: UInt16?

    mutating func probe() -> BrightnessRecoveryPolicy.ChannelOutcome {
        var accepted = false
        for _ in 0..<3 {
            guard !Task.isCancelled else { break }
            guard link.send(DisplayDDC.request(.luminance)) else { continue }
            accepted = true
            if let reply = link.receive(DisplayDDC.replyLength).flatMap({ DisplayDDC.parse($0, .luminance) }) {
                maximum = reply.maximum
                return .live(current: reply.current, maximum: reply.maximum)
            }
        }
        return BrightnessRecoveryPolicy.channelOutcome(writeAccepted: accepted, reply: nil)
    }

    func write(_ level: Double) -> Bool {
        guard !Task.isCancelled else { return false }
        let value = DisplayDDC.deviceValue(level, maximum: maximum ?? DisplayDDC.assumedMaximum)
        return link.send(DisplayDDC.write(.luminance, value))
    }
}

extension BrightnessDDCLink {
    /// Only a parsed reply proves the monitor has the control, so a silent one reads nil.
    func read(_ code: DisplayDDC.Code, attempts: Int) -> (current: UInt16, maximum: UInt16)? {
        for _ in 0..<attempts {
            guard !Task.isCancelled else { return nil }
            guard send(DisplayDDC.request(code)) else { continue }
            if let reply = receive(DisplayDDC.replyLength).flatMap({ DisplayDDC.parse($0, code) }) { return reply }
        }
        return nil
    }
}
