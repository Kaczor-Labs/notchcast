import Foundation

/// Finds ZIPs named in a Windows code page, which The Unarchiver decodes and HatchZip does not.
nonisolated enum ZIPNameEncoding {
    /// The end record plus the longest comment it may carry.
    static let tailLength = 22 + 65_535

    /// Where the central directory starts and how long it is, from the file's last `tailLength` bytes.
    static func directory(tail: Data) -> (offset: UInt64, size: UInt64)? {
        let bytes = [UInt8](tail)
        guard bytes.count >= 22 else { return nil }
        for start in stride(from: bytes.count - 22, through: 0, by: -1)
        where bytes[start] == 0x50 && bytes[start + 1] == 0x4B && bytes[start + 2] == 0x05 && bytes[start + 3] == 0x06 {
            let size = read32(bytes, start + 12)
            let offset = read32(bytes, start + 16)
            // ZIP64 keeps the real values elsewhere; such archives are new enough to name in UTF-8.
            guard size != 0xFFFF_FFFF, offset != 0xFFFF_FFFF else { return nil }
            return (UInt64(offset), UInt64(size))
        }
        return nil
    }

    /// True when a name without the UTF-8 flag (bit 11) is not valid UTF-8 either.
    static func hasLegacyNames(directory: Data) -> Bool {
        let bytes = [UInt8](directory)
        var index = 0
        while index + 46 <= bytes.count, read32(bytes, index) == 0x0201_4B50 {
            let flags = read16(bytes, index + 8)
            let nameLength = read16(bytes, index + 28)
            let skip = 46 + nameLength + read16(bytes, index + 30) + read16(bytes, index + 32)
            guard index + 46 + nameLength <= bytes.count else { return false }
            let name = bytes[(index + 46)..<(index + 46 + nameLength)]
            if flags & 0x0800 == 0, name.contains(where: { $0 >= 0x80 }), String(validating: name, as: UTF8.self) == nil {
                return true
            }
            index += skip
        }
        return false
    }

    private static func read16(_ bytes: [UInt8], _ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }

    private static func read32(_ bytes: [UInt8], _ at: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[at + $1]) << (8 * $1) }
    }
}
