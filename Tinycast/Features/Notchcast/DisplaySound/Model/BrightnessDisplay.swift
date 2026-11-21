import Foundation

struct BrightnessDisplay: Identifiable, Equatable, Codable, Sendable {
    struct ID: Hashable, Codable, Sendable {
        let rawValue: UInt32
        let uuid: String

        init(rawValue: UInt32, uuid: String) {
            self.rawValue = rawValue
            self.uuid = uuid.uppercased()
        }
    }

    enum Control: Equatable, Codable, Sendable {
        case system, ddc, writeOnlyDDC, software
    }

    let id: ID
    let name: String
    let isBuiltIn: Bool
    let control: Control
    var level: BrightnessLevel
}
