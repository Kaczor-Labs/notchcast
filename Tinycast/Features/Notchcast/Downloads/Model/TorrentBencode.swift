import Foundation

/// A strict bencode reader: no duplicate keys, no trailing bytes, no leading zeros.
nonisolated enum TorrentBencode: Equatable, Sendable {
    case integer(Int64)
    case bytes(Data)
    case list([TorrentBencode])
    case dictionary([Data: TorrentBencode])

    struct Invalid: Error, Equatable {}

    /// The value and the byte range of its top-level `info` dictionary, which the info hash covers.
    static func parse(_ data: Data) throws(Invalid) -> (value: TorrentBencode, info: Range<Int>?) {
        var reader = Reader(bytes: [UInt8](data))
        let value = try reader.value(depth: 0)
        guard reader.index == reader.bytes.count else { throw Invalid() }
        return (value, reader.info)
    }

    subscript(key: String) -> TorrentBencode? {
        guard case .dictionary(let entries) = self else { return nil }
        return entries[Data(key.utf8)]
    }

    var text: String? {
        guard case .bytes(let data) = self else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private struct Reader {
        static let maxDepth = 64
        let bytes: [UInt8]
        var index = 0
        var info: Range<Int>?

        mutating func value(depth: Int) throws(Invalid) -> TorrentBencode {
            guard depth < Self.maxDepth, index < bytes.count else { throw Invalid() }
            switch bytes[index] {
            case UInt8(ascii: "i"):
                index += 1
                let number = try integer(until: UInt8(ascii: "e"))
                return .integer(number)
            case UInt8(ascii: "l"):
                index += 1
                var items: [TorrentBencode] = []
                while try !atEnd() { items.append(try value(depth: depth + 1)) }
                return .list(items)
            case UInt8(ascii: "d"):
                index += 1
                var entries: [Data: TorrentBencode] = [:]
                while try !atEnd() {
                    let key = try string()
                    let start = index
                    let item = try value(depth: depth + 1)
                    guard entries.updateValue(item, forKey: key) == nil else { throw Invalid() }
                    if depth == 0, key == Data("info".utf8) { info = start..<index }
                }
                return .dictionary(entries)
            default:
                return .bytes(try string())
            }
        }

        private mutating func atEnd() throws(Invalid) -> Bool {
            guard index < bytes.count else { throw Invalid() }
            guard bytes[index] == UInt8(ascii: "e") else { return false }
            index += 1
            return true
        }

        private mutating func string() throws(Invalid) -> Data {
            let length = try integer(until: UInt8(ascii: ":"))
            guard length >= 0, length <= bytes.count - index else { throw Invalid() }
            let start = index
            index += Int(length)
            return Data(bytes[start..<index])
        }

        private mutating func integer(until terminator: UInt8) throws(Invalid) -> Int64 {
            guard let end = bytes[index...].firstIndex(of: terminator), end > index, end - index <= 20 else {
                throw Invalid()
            }
            let digits = bytes[index..<end]
            guard let text = String(bytes: digits, encoding: .ascii) else { throw Invalid() }
            let negative = text.hasPrefix("-")
            let magnitude = negative ? text.dropFirst() : Substring(text)
            guard !magnitude.isEmpty, magnitude.allSatisfy(\.isASCII), magnitude.allSatisfy(\.isNumber),
                  magnitude == "0" || !magnitude.hasPrefix("0"), !(negative && magnitude == "0"),
                  !(negative && terminator == UInt8(ascii: ":")), let number = Int64(text) else { throw Invalid() }
            index = end + 1
            return number
        }
    }
}
