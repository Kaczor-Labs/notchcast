import Foundation

/// Reads another app with `core/getd` Apple Events, 5 s each; in Core because two add-ons read Finder.
nonisolated enum NotchcastAppleEvents {
    /// macOS refusing the event: a denied Automation grant (-1743) or one it would have to ask for (-1744).
    static let refused = [-1743, -1744]
    static let timedOut = -1712

    /// One object-specifier hop: a named property, or the first element of a class.
    struct Hop {
        let want: NSAppleEventDescriptor
        let form: NSAppleEventDescriptor
        let seld: NSAppleEventDescriptor

        static func property(_ name: String) -> Hop {
            Hop(want: .init(typeCode: code("prop")), form: .init(enumCode: code("prop")), seld: .init(typeCode: code(name)))
        }

        static func first(_ kind: String) -> Hop {
            Hop(want: .init(typeCode: code(kind)), form: .init(enumCode: code("indx")), seld: .init(int32: 1))
        }
    }

    /// Finder's selection as file URLs: one event for the selection, then one per selected item.
    static func finderSelection(refusing: (Int) throws -> Void) throws -> [String] {
        let finder = "com.apple.finder"
        return try values(finder, [.property("sele")], refusing: refusing).flatMap {
            try values(finder, [.property("pURL")], from: $0, refusing: refusing)
        }.compactMap(\.stringValue)
    }

    /// The reply's items; a failed read hands its status to `refusing`, and is empty unless that throws.
    static func values(
        _ bundleID: String, _ path: [Hop], from root: NSAppleEventDescriptor = .null(),
        refusing: (Int) throws -> Void
    ) throws -> [NSAppleEventDescriptor] {
        try Task.checkCancellation()
        let object = path.reduce(Optional(root)) { from, hop in
            let record = NSAppleEventDescriptor.record()
            for (key, value) in [("from", from), ("want", hop.want), ("form", hop.form), ("seld", hop.seld)] {
                guard let value else { return nil }
                record.setDescriptor(value, forKeyword: code(key))
            }
            return record.coerce(toDescriptorType: code("obj "))
        }
        guard let object else { return [] }
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        let event = NSAppleEventDescriptor(
            eventClass: code("core"), eventID: code("getd"), targetDescriptor: target, returnID: -1, transactionID: 0)
        event.setParam(object, forKeyword: code("----"))
        let reply: NSAppleEventDescriptor
        do {
            reply = try event.sendEvent(options: [.waitForReply, .canInteract], timeout: 5)
        } catch {
            try refusing((error as NSError).code)
            return []
        }
        try Task.checkCancellation()
        let status = Int(reply.paramDescriptor(forKeyword: code("errn"))?.int32Value ?? 0)
        guard status == 0 else {
            try refusing(status)
            return []
        }
        guard let answer = reply.paramDescriptor(forKeyword: code("----")) else { return [] }
        guard answer.descriptorType == code("list") else { return [answer] }
        return (0..<answer.numberOfItems).compactMap { answer.atIndex($0 + 1) }
    }

    private static func code(_ text: String) -> UInt32 {
        text.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }
}
