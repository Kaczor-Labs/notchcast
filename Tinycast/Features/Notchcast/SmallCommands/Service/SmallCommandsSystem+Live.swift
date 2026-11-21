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
                let bundleID = app.bundleIdentifier, let browser = SmallCommandsAppleEvents.browser(bundleID)
            else { return nil }
            return try await SmallCommandsAppleEvents.address(bundleID, browser: browser)
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

/// The front browser's address and Finder's selection, through the core's Apple Event reader.
private nonisolated enum SmallCommandsAppleEvents {
    typealias Hop = NotchcastAppleEvents.Hop

    enum Browser: Sendable {
        case safari, chromium

        var path: [Hop] {
            switch self {
            case .safari: [.first("docu"), .property("pURL")]
            case .chromium: [.first("cwin"), .property("acTa"), .property("URL ")]
            }
        }
    }

    private static let browsers: [String: Browser] = [
        "com.apple.Safari": .safari,
        "com.apple.SafariTechnologyPreview": .safari,
        "com.google.Chrome": .chromium,
        "com.google.Chrome.canary": .chromium,
        "com.brave.Browser": .chromium,
        "com.microsoft.edgemac": .chromium,
        "company.thebrowser.Browser": .chromium,
        "com.vivaldi.Vivaldi": .chromium,
        "com.operasoftware.Opera": .chromium,
        "org.chromium.Chromium": .chromium,
    ]

    static func browser(_ bundleID: String) -> Browser? { browsers[bundleID] }

    @concurrent
    static func address(_ bundleID: String, browser: Browser) async throws -> String? {
        try NotchcastAppleEvents.values(bundleID, browser.path, refusing: stop(.browserNeedsAutomation))
            .first?.stringValue
    }

    @concurrent
    static func finderSelection() async throws -> [URL] {
        try NotchcastAppleEvents.finderSelection(refusing: stop(.finderNeedsAutomation))
            .compactMap(URL.init(string:)).filter(\.isFileURL)
    }

    /// A refused grant and a timeout stop the command; anything else reads as empty.
    private static func stop(_ denied: SmallCommandsFailure) -> (Int) throws -> Void {
        { status in
            if NotchcastAppleEvents.refused.contains(status) { throw denied }
            if status == NotchcastAppleEvents.timedOut { throw SmallCommandsFailure.appTimedOut }
        }
    }
}
