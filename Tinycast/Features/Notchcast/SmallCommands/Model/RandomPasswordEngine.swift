import Foundation

/// 24 characters without look-alikes (l, o, I, O, 0, 1), always with a digit and a sign.
nonisolated enum RandomPasswordEngine {
    enum Failure: Error { case entropyUnavailable }

    static let length = 24
    static let letters = Array("abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ")
    static let digits = Array("23456789")
    static let signs = Array("!@#$*^&%")
    static let alphabet = letters + digits + signs

    /// Bytes past the last full alphabet cycle are dropped, so no character leans.
    static func make(randomBytes: (Int) throws -> [UInt8]) throws -> String {
        let limit = 256 - 256 % alphabet.count
        var picked: [Character] = []
        for _ in 0..<128 {
            for byte in try randomBytes(length * 2) where Int(byte) < limit {
                picked.append(alphabet[Int(byte) % alphabet.count])
                guard picked.count == length else { continue }
                if picked.contains(where: digits.contains), picked.contains(where: signs.contains) {
                    return String(picked)
                }
                picked.removeAll(keepingCapacity: true)
            }
        }
        throw Failure.entropyUnavailable
    }
}
