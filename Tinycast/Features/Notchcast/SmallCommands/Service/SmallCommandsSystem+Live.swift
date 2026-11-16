import AppKit
import Security

extension SmallCommandsSystem {
    static let live = SmallCommandsSystem(
        clipboardText: { NSPasteboard.general.string(forType: .string) },
        copy: { text, concealed in
            guard concealed else { return Paster.copyPlainText(text) }
            let pasteboard = NSPasteboard.general
            let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
            pasteboard.clearContents()
            pasteboard.declareTypes([.string, concealedType], owner: nil)
            return pasteboard.setString(text, forType: .string) && pasteboard.setData(Data(), forType: concealedType)
        },
        randomBytes: { count in
            var bytes = [UInt8](repeating: 0, count: count)
            guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
                throw RandomPasswordEngine.Failure.entropyUnavailable
            }
            return bytes
        },
        browserAddress: {
            guard let app = NSWorkspace.shared.menuBarOwningApplication,
                app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                let bundleID = app.bundleIdentifier, let steps = SmallCommandsAppleEvents.addressSteps(bundleID)
            else { return nil }
            return try await SmallCommandsAppleEvents.address(bundleID, steps: steps)
        },
        fetch: { try await ShortenLinkSession.fetch($0) },
        makeAirDrop: {
            AirDropService(
                selection: { try await SmallCommandsAppleEvents.finderSelection() },
                makeService: { files in
                    NSSharingService(named: .sendViaAirDrop).flatMap { $0.canPerform(withItems: files) ? $0 : nil }
                },
                perform: { $0.perform(withItems: $1) },
                activate: { NSApp.activate() })
        }
    )
}

/// Reads the front browser's address and Finder's selection with `core/getd` Apple Events.
private nonisolated enum SmallCommandsAppleEvents {
    enum Step: Sendable {
        case first(String)
        case property(String)
    }

    private static let safari: [Step] = [.first("docu"), .property("pURL")]
    private static let chromium: [Step] = [.first("cwin"), .property("acTa"), .property("URL ")]
    private static let browsers: [String: [Step]] = [
        "com.apple.Safari": safari,
        "com.apple.SafariTechnologyPreview": safari,
        "com.google.Chrome": chromium,
        "com.google.Chrome.canary": chromium,
        "com.brave.Browser": chromium,
        "com.microsoft.edgemac": chromium,
        "company.thebrowser.Browser": chromium,
        "com.vivaldi.Vivaldi": chromium,
        "com.operasoftware.Opera": chromium,
        "org.chromium.Chromium": chromium,
    ]

    static func addressSteps(_ bundleID: String) -> [Step]? { browsers[bundleID] }

    @concurrent
    static func address(_ bundleID: String, steps: [Step]) async throws -> String? {
        try get(bundleID, steps: steps, denied: .browserNeedsAutomation).first?.stringValue
    }

    @concurrent
    static func finderSelection() async throws -> [URL] {
        let finder = "com.apple.finder"
        return try get(finder, steps: [.property("sele")], denied: .finderNeedsAutomation).flatMap { item in
            try get(finder, steps: [.property("pURL")], container: item, denied: .finderNeedsAutomation)
        }.compactMap { $0.stringValue.flatMap(URL.init(string:)) }.filter(\.isFileURL)
    }

    private static func get(
        _ bundleID: String, steps: [Step], container: NSAppleEventDescriptor = .null(),
        denied: SmallCommandsFailure
    ) throws -> [NSAppleEventDescriptor] {
        try Task.checkCancellation()
        var specifier = container
        for step in steps {
            let record = NSAppleEventDescriptor.record()
            record.setDescriptor(specifier, forKeyword: code("from"))
            switch step {
            case .first(let name):
                record.setDescriptor(NSAppleEventDescriptor(typeCode: code(name)), forKeyword: code("want"))
                record.setDescriptor(NSAppleEventDescriptor(enumCode: code("indx")), forKeyword: code("form"))
                record.setDescriptor(NSAppleEventDescriptor(int32: 1), forKeyword: code("seld"))
            case .property(let name):
                record.setDescriptor(NSAppleEventDescriptor(typeCode: code("prop")), forKeyword: code("want"))
                record.setDescriptor(NSAppleEventDescriptor(enumCode: code("prop")), forKeyword: code("form"))
                record.setDescriptor(NSAppleEventDescriptor(typeCode: code(name)), forKeyword: code("seld"))
            }
            guard let object = record.coerce(toDescriptorType: code("obj ")) else { return [] }
            specifier = object
        }
        let event = NSAppleEventDescriptor(
            eventClass: code("core"), eventID: code("getd"),
            targetDescriptor: NSAppleEventDescriptor(bundleIdentifier: bundleID),
            returnID: -1, transactionID: 0)
        event.setParam(specifier, forKeyword: code("----"))
        let reply: NSAppleEventDescriptor
        do {
            reply = try event.sendEvent(options: [.waitForReply, .canInteract], timeout: 5)
        } catch let error as NSError {
            return try empty(error.code, denied: denied)
        }
        if let error = reply.paramDescriptor(forKeyword: code("errn")), error.int32Value != 0 {
            return try empty(Int(error.int32Value), denied: denied)
        }
        try Task.checkCancellation()
        guard let answer = reply.paramDescriptor(forKeyword: code("----")) else { return [] }
        guard answer.descriptorType == code("list") else { return [answer] }
        return answer.numberOfItems > 0 ? (1...answer.numberOfItems).compactMap { answer.atIndex($0) } : []
    }

    /// -1743 is a denied Automation grant, -1712 a timeout; anything else reads as empty.
    private static func empty(_ status: Int, denied: SmallCommandsFailure) throws -> [NSAppleEventDescriptor] {
        switch status {
        case -1743: throw denied
        case -1712: throw SmallCommandsFailure.appTimedOut
        default: return []
        }
    }

    private static func code(_ text: String) -> UInt32 {
        text.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }
}
