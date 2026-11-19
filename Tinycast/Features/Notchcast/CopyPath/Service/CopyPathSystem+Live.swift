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
            webArea: { try await CopyPathAccessibility.webArea(pid: $0) },
            document: { try await CopyPathAccessibility.document(pid: $0, window: $1) },
            selectedTabs: { try await CopyPathTabLinks.selectedTabs(pid: $0) },
            browserCopy: { try await CopyPathTabLinks.browserCopy(pid: $0) }),
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

/// Reads `AXDocument` or a Gecko page's `AXURL`; the 1 s timeout is per element, never inherited.
private nonisolated enum CopyPathAccessibility {
    static let timeout: Float = 1

    /// A window's elements walked before giving up; a long tab sidebar alone holds hundreds.
    static let maxElements = 2000

    @concurrent
    static func document(pid: Int32, window: CopyPathResolver.Window) async throws -> String? {
        guard AXIsProcessTrusted() else { throw CopyPathFailure.accessibility }
        let attribute = window == .focused ? kAXFocusedWindowAttribute : kAXMainWindowAttribute
        guard let window = try element(AXUIElementCreateApplication(pid), attribute) else { return nil }
        return try read(window, kAXDocumentAttribute) as? String
    }

    /// The page holding focus, else the focused window's first page, read as its web area's `AXURL`.
    @concurrent
    static func webArea(pid: Int32) async throws -> String? {
        guard AXIsProcessTrusted() else { throw CopyPathFailure.accessibility }
        let app = AXUIElementCreateApplication(pid)
        // Gecko builds its tree only once a client asks the application for its role.
        _ = try read(app, kAXRoleAttribute)
        if let address = try pageAddress(app) { return address }
        // On first activation the pages arrive from Gecko's content processes a moment later.
        try await Task.sleep(for: .milliseconds(500))
        return try pageAddress(app)
    }

    private static func pageAddress(_ app: AXUIElement) throws -> String? {
        var element = try self.element(app, kAXFocusedUIElementAttribute)
        for _ in 0..<maxElements {
            guard let current = element else { break }
            if let address = try address(current) { return address }
            element = try self.element(current, kAXParentAttribute)
        }
        guard let window = try self.element(app, kAXFocusedWindowAttribute) else { return nil }
        var queue = [window]
        var index = 0
        while index < queue.count, index < maxElements {
            if let address = try address(queue[index]) { return address }
            queue += try read(queue[index], kAXChildrenAttribute) as? [AXUIElement] ?? []
            index += 1
        }
        return nil
    }

    /// A page's `AXURL`; Gecko's window and panels are `chrome:` or `moz-extension:` web areas too.
    private static func address(_ element: AXUIElement) throws -> String? {
        guard try read(element, kAXRoleAttribute) as? String == "AXWebArea",
            let url = try read(element, kAXURLAttribute) as? URL,
            ["http", "https", "file"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url.absoluteString
    }

    private static func element(_ element: AXUIElement, _ attribute: String) throws -> AXUIElement? {
        guard let value = try read(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func read(_ element: AXUIElement, _ attribute: String) throws -> CFTypeRef? {
        try Task.checkCancellation()
        AXUIElementSetMessagingTimeout(element, timeout)
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return try CopyPathStatus.accessibility(status.rawValue) ? value : nil
    }
}
