/// JavaScript compares string code units, without Unicode canonical equivalence.
public func sameString(_ lhs: String?, _ rhs: String?) -> Bool {
    switch (lhs, rhs) {
    case (nil, nil): true
    case let (lhs?, rhs?): lhs.utf8.elementsEqual(rhs.utf8)
    default: false
    }
}

private struct StringIdentity: Hashable, Sendable {
    let value: String
    static func == (lhs: Self, rhs: Self) -> Bool { sameString(lhs.value, rhs.value) }
    func hash(into hasher: inout Hasher) {
        for byte in value.utf8 { hasher.combine(byte) }
    }
}

/// A string-keyed map with JavaScript identity rather than Swift's canonical equivalence.
public struct StringMap<Value>: ExpressibleByDictionaryLiteral, Sequence {
    private var storage: [StringIdentity: Value] = [:]

    public init(dictionaryLiteral elements: (String, Value)...) {
        for (key, value) in elements { self[key] = value }
    }

    public subscript(key: String) -> Value? {
        get { storage[StringIdentity(value: key)] }
        set { storage[StringIdentity(value: key)] = newValue }
    }

    public var keys: [String] { storage.keys.map(\.value) }
    public var values: [Value] { Array(storage.values) }
    public var count: Int { storage.count }
    public func makeIterator() -> AnyIterator<(key: String, value: Value)> {
        var iterator = storage.makeIterator()
        return AnyIterator { iterator.next().map { (key: $0.key.value, value: $0.value) } }
    }

    public func filter(_ included: ((key: String, value: Value)) throws -> Bool) rethrows -> Self {
        var result: Self = [:]
        for element in self where try included(element) { result[element.key] = element.value }
        return result
    }
}

extension StringMap: Sendable where Value: Sendable {}

struct StringSet: ExpressibleByArrayLiteral, Sequence {
    private var storage: Set<StringIdentity> = []
    init(arrayLiteral elements: String...) { for value in elements { insert(value) } }
    init(_ elements: some Sequence<String>) { for value in elements { insert(value) } }
    func contains(_ value: String) -> Bool { storage.contains(StringIdentity(value: value)) }
    mutating func insert(_ value: String) { storage.insert(StringIdentity(value: value)) }
    mutating func remove(_ value: String) { storage.remove(StringIdentity(value: value)) }
    func makeIterator() -> IndexingIterator<[String]> { storage.map(\.value).makeIterator() }
    func filter(_ included: (String) throws -> Bool) rethrows -> Self {
        StringSet(try Array(self).filter(included))
    }
}

extension String {
    public var islandIdentity: [UInt8] { Array(utf8) }
}
