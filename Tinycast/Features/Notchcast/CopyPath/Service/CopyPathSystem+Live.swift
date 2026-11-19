import AppKit
// `@preconcurrency` downgrades AX diagnostics: the attribute names are constant C globals.
@preconcurrency import ApplicationServices

extension CopyPathSystem {
    static let live = CopyPathSystem(
        frontApp: {
            guard let app = NSWorkspace.shared.menuBarOwningApplication,
                app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
            return CopyPathApp(bundleID: app.bundleIdentifier, pid: app.processIdentifier)
        },
        home: FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false),
        reader: CopyPathReader(
            finderSelection: { try await CopyPathAppleEvents.finderSelection() },
            finderFolder: { try await CopyPathAppleEvents.finderFolder() },
            browserAddress: { try await CopyPathAppleEvents.browserAddress($0, kind: $1) },
            document: { try await CopyPathAccessibility.document(pid: $0, window: $1) }),
        copy: { Paster.copyPlainText($0) },
        openSettings: { failure in
            guard failure != .accessibility else { return Permissions.openAccessibilitySettings() }
            let pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
            if let url = URL(string: pane) { NSWorkspace.shared.open(url) }
        }
    )
}

/// Reads Finder and browsers through the core's Apple Event reader, off the caller's actor.
private nonisolated enum CopyPathAppleEvents {
    @concurrent
    static func finderSelection() async throws -> [String] {
        try NotchcastAppleEvents.finderSelection(refusing: stop(.finderAutomation))
    }

    @concurrent
    static func finderFolder() async throws -> String? {
        let path: [NotchcastAppleEvents.Hop] = [.first("brow"), .property("fvtg"), .property("pURL")]
        return try NotchcastAppleEvents.values(CopyPathResolver.finder, path, refusing: stop(.finderAutomation))
            .first?.stringValue
    }

    @concurrent
    static func browserAddress(_ bundleID: String, kind: CopyPathResolver.Browser) async throws -> String? {
        let path: [NotchcastAppleEvents.Hop] = switch kind {
        case .safari: [.first("docu"), .property("pURL")]
        case .chromium: [.first("cwin"), .property("acTa"), .property("URL ")]
        }
        return try NotchcastAppleEvents.values(bundleID, path, refusing: stop(.browserAutomation)).first?.stringValue
    }

    /// `CopyPathStatus` decides which failed reads are nothing there and which stop the run.
    private static func stop(_ denied: CopyPathFailure) -> (Int) throws -> Void {
        { _ = try CopyPathStatus.appleEvent($0, denied: denied) }
    }
}

/// Reads one window's `AXDocument`; the 1 s timeout is per element, never inherited, so each gets it.
private nonisolated enum CopyPathAccessibility {
    static let timeout: Float = 1

    @concurrent
    static func document(pid: Int32, window: CopyPathResolver.Window) async throws -> String? {
        guard AXIsProcessTrusted() else { throw CopyPathFailure.accessibility }
        let attribute = window == .focused ? kAXFocusedWindowAttribute : kAXMainWindowAttribute
        guard let value = try read(AXUIElementCreateApplication(pid), attribute),
            CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return try read(unsafeDowncast(value, to: AXUIElement.self), kAXDocumentAttribute) as? String
    }

    private static func read(_ element: AXUIElement, _ attribute: String) throws -> CFTypeRef? {
        try Task.checkCancellation()
        AXUIElementSetMessagingTimeout(element, timeout)
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return try CopyPathStatus.accessibility(status.rawValue) ? value : nil
    }
}
