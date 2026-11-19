import Foundation

/// The MCCS VCP packets a monitor speaks over DDC/CI: luminance, speaker volume and mute.
enum DisplayDDC {
    enum Code: UInt8, Sendable {
        case luminance = 0x10, volume = 0x62, mute = 0x8D
    }

    static let chip: UInt32 = 0x37
    static let host: UInt32 = 0x51
    static let replyLength = 11
    /// The MCCS scale most monitors use; a monitor that never replies never says otherwise.
    static let assumedMaximum: UInt16 = 100

    static func request(_ code: Code) -> [UInt8] { seal([0x82, 0x01, code.rawValue]) }

    static func write(_ code: Code, _ value: UInt16) -> [UInt8] {
        seal([0x84, 0x03, code.rawValue, UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    static func parse(_ reply: [UInt8], _ code: Code) -> (current: UInt16, maximum: UInt16)? {
        guard reply.count == replyLength, reply[0] == 0x6E, reply[1] == 0x88,
              reply[2] == 0x02, reply[3] == 0, reply[4] == code.rawValue,
              reply.reduce(UInt8(0x50), ^) == 0 else { return nil }
        let maximum = UInt16(reply[6]) << 8 | UInt16(reply[7])
        let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
        guard maximum > 0, current <= maximum else { return nil }
        return (current, maximum)
    }

    /// A 0…1 share on the monitor's own scale; anything below 0 writes 0.
    static func deviceValue(_ share: Double, maximum: UInt16) -> UInt16 {
        guard share.isFinite else { return 0 }
        return UInt16((min(max(share, 0), 1) * Double(maximum)).rounded())
    }

    static func share(_ value: UInt16, maximum: UInt16) -> Double {
        maximum == 0 ? 0 : min(Double(value) / Double(maximum), 1)
    }

    /// MCCS 0x8D: 1 mutes, 2 unmutes; any other value is a monitor using the code for something else.
    static func muteValue(_ muted: Bool) -> UInt16 { muted ? 1 : 2 }

    static func muted(_ value: UInt16) -> Bool? {
        switch value {
        case 1: true
        case 2: false
        default: nil
        }
    }

    static func seal(_ body: [UInt8]) -> [UInt8] {
        body + [body.reduce(UInt8(0x6E ^ 0x51), ^)]
    }
}
