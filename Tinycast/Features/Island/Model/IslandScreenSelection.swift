enum IslandScreenSelection {
    static func choose(available: [UInt32], preferred: UInt32?, retained: UInt32?) -> UInt32? {
        if let preferred, available.contains(preferred) { return preferred }
        if let retained, available.contains(retained) { return retained }
        return available.first
    }
}
