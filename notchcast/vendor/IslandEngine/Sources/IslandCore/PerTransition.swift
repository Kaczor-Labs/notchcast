import Foundation

/// Which motion a presentation change uses, in upstream's `shapeTransitions` order.
public enum ShapeTransition: String, CaseIterable, Codable, Sendable {
    /// Idle to compact.
    case appear
    /// Compact to expanded, same activity.
    case expand
    /// The same, out of a long-press swell.
    case pressExpand
    /// Idle straight to expanded.
    case appearExpand
    /// To expanded for a different activity than the one showing, through idle.
    case swap
    /// Expanded back to compact after a press outside or `collapse()`.
    case collapse
    /// The same when an alert's hold runs out.
    case alertCollapse
    /// Expanded back to the split.
    case collapseSplit
    /// A second activity arrives.
    case split
    /// A second activity leaves.
    case unsplit
    /// Compact (or split) back to idle.
    case dismiss
    /// Content changed size inside the same presentation.
    case resize
}

/// The expanded view's four regions, as ActivityKit names them.
public enum ExpandedRegion: String, CaseIterable, Codable, Sendable {
    case leading
    case center
    case trailing
    case bottom
}

private struct RecordKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init(_ stringValue: String) { self.stringValue = stringValue }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// A value for each shape transition: upstream's `Record<ShapeTransition, Value>`. Encoded as a
/// JSON object keyed by the transition's name.
public struct PerTransition<Value> {
    private var storage: [ShapeTransition: Value]

    /// Traps when a case is missing.
    public init(_ values: [ShapeTransition: Value]) {
        for transition in ShapeTransition.allCases {
            precondition(values[transition] != nil, "missing value for \(transition.rawValue)")
        }
        storage = values
    }

    public subscript(_ transition: ShapeTransition) -> Value {
        get { storage[transition]! }
        set { storage[transition] = newValue }
    }
}

extension PerTransition: Sendable where Value: Sendable {}
extension PerTransition: Equatable where Value: Equatable {}

extension PerTransition: Codable where Value: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: RecordKey.self)
        var values: [ShapeTransition: Value] = [:]
        for transition in ShapeTransition.allCases {
            values[transition] = try container.decode(Value.self, forKey: RecordKey(transition.rawValue))
        }
        storage = values
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: RecordKey.self)
        for transition in ShapeTransition.allCases {
            try container.encode(storage[transition]!, forKey: RecordKey(transition.rawValue))
        }
    }
}

/// Values for some keys only, encoded as a JSON object that holds just those keys: upstream's
/// `Partial<Record<Key, Value>>`.
public struct SparseTable<Key: RawRepresentable & CaseIterable & Hashable, Value>
where Key.RawValue == String {
    private var storage: [Key: Value]

    public init(_ values: [Key: Value] = [:]) {
        storage = values
    }

    public subscript(_ key: Key) -> Value? {
        get { storage[key] }
        set { storage[key] = newValue }
    }
}

extension SparseTable: Sendable where Value: Sendable, Key: Sendable {}
extension SparseTable: Equatable where Value: Equatable {}

extension SparseTable: Codable where Value: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: RecordKey.self)
        var values: [Key: Value] = [:]
        for name in container.allKeys {
            guard let key = Key(rawValue: name.stringValue) else {
                throw DecodingError.dataCorruptedError(
                    forKey: name, in: container, debugDescription: "unknown key \(name.stringValue)")
            }
            values[key] = try container.decode(Value.self, forKey: name)
        }
        storage = values
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: RecordKey.self)
        for key in Key.allCases {
            if let value = storage[key] {
                try container.encode(value, forKey: RecordKey(key.rawValue))
            }
        }
    }
}

/// Values for some shape transitions: upstream's `Partial<Record<ShapeTransition, Value>>`.
public typealias PartialPerTransition<Value> = SparseTable<ShapeTransition, Value>

/// Values for some expanded regions: upstream's `Partial<Record<ExpandedRegion, Value>>`.
public typealias PerRegion<Value> = SparseTable<ExpandedRegion, Value>
