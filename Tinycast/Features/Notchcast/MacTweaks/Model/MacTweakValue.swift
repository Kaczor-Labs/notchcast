// Adapted from RemoveMacAI (omlahore, 12cef18, MIT) and Peel (Dragos Tugui, 2023079, GPL-3.0).
import Foundation

enum MacTweakValue: Codable, Equatable, Sendable {
    case bool(Bool)
    case integer(Int64)
    case real(Double)
    case string(String)
    case data(Data)
    case date(Date)
    case array([Self])
    case dictionary([String: Self])

    func matches(_ stored: Self?) -> Bool {
        guard let stored else { return false }
        if self == stored { return true }
        switch (self, stored) {
        case (.bool(let value), .integer(let number)):
            return number == (value ? 1 : 0)
        case (.bool(let value), .string(let text)):
            switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "yes", "true", "1", "y", "t": return value
            case "no", "false", "0", "n", "f": return !value
            default: return false
            }
        case (.real(let value), .integer(let number)):
            return Int64(exactly: value) == number
        case (.integer(let number), .real(let value)):
            return Int64(exactly: value) == number
        case (.integer(let number), .string(let text)):
            return Int64(text.trimmingCharacters(in: .whitespaces)) == number
        case (.real(let value), .string(let text)):
            return Double(text.trimmingCharacters(in: .whitespaces)) == value
        default:
            return false
        }
    }
}
