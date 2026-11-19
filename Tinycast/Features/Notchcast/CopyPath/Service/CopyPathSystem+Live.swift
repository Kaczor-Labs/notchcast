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

/// Reads Finder and browsers with `core/getd` Apple Events, 5 s each.
private nonisolated enum CopyPathAppleEvents {
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

    @concurrent
    static func finderSelection() async throws -> [String] {
        let items = try values(CopyPathResolver.finder, [.property("sele")], denied: .finderAutomation)
        return try items.flatMap {
            try values(CopyPathResolver.finder, [.property("pURL")], from: $0, denied: .finderAutomation)
        }.compactMap(\.stringValue)
    }

    @concurrent
    static func finderFolder() async throws -> String? {
        let path: [Hop] = [.first("brow"), .property("fvtg"), .property("pURL")]
        return try values(CopyPathResolver.finder, path, denied: .finderAutomation).first?.stringValue
    }

    @concurrent
    static func browserAddress(_ bundleID: String, kind: CopyPathResolver.Browser) async throws -> String? {
        let path: [Hop] = switch kind {
        case .safari: [.first("docu"), .property("pURL")]
        case .chromium: [.first("cwin"), .property("acTa"), .property("URL ")]
        }
        return try values(bundleID, path, denied: .browserAutomation).first?.stringValue
    }

    /// The reply's items; `CopyPathStatus` decides which errors read as none and which stop the run.
    private static func values(
        _ bundleID: String, _ path: [Hop], from root: NSAppleEventDescriptor = .null(), denied: CopyPathFailure
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
            _ = try CopyPathStatus.appleEvent((error as NSError).code, denied: denied)
            return []
        }
        try Task.checkCancellation()
        let status = Int(reply.paramDescriptor(forKeyword: code("errn"))?.int32Value ?? 0)
        guard try CopyPathStatus.appleEvent(status, denied: denied) else { return [] }
        guard let answer = reply.paramDescriptor(forKeyword: code("----")) else { return [] }
        guard answer.descriptorType == code("list") else { return [answer] }
        return (0..<answer.numberOfItems).compactMap { answer.atIndex($0 + 1) }
    }

    private static func code(_ text: String) -> UInt32 {
        text.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
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
