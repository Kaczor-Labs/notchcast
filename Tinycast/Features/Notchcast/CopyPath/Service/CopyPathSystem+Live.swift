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
            document: { try await CopyPathAccessibility.document(pid: $0) }),
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
    enum Step {
        case first(String)
        case property(String)
    }

    @concurrent
    static func finderSelection() async throws -> [String] {
        try get(CopyPathResolver.finder, [.property("sele")], denied: .finderAutomation).flatMap { item in
            try get(CopyPathResolver.finder, [.property("pURL")], in: item, denied: .finderAutomation)
        }.compactMap(\.stringValue)
    }

    @concurrent
    static func finderFolder() async throws -> String? {
        let steps: [Step] = [.first("brow"), .property("fvtg"), .property("pURL")]
        return try get(CopyPathResolver.finder, steps, denied: .finderAutomation).first?.stringValue
    }

    @concurrent
    static func browserAddress(_ bundleID: String, kind: CopyPathResolver.Browser) async throws -> String? {
        let steps: [Step] = switch kind {
        case .safari: [.first("docu"), .property("pURL")]
        case .chromium: [.first("cwin"), .property("acTa"), .property("URL ")]
        }
        return try get(bundleID, steps, denied: .browserAutomation).first?.stringValue
    }

    private static func get(
        _ bundleID: String, _ steps: [Step], in container: NSAppleEventDescriptor = .null(),
        denied: CopyPathFailure
    ) throws -> [NSAppleEventDescriptor] {
        try Task.checkCancellation()
        var specifier = container
        for step in steps {
            let record = NSAppleEventDescriptor.record()
            record.setDescriptor(specifier, forKeyword: code("from"))
            switch step {
            case .first(let kind):
                record.setDescriptor(NSAppleEventDescriptor(typeCode: code(kind)), forKeyword: code("want"))
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
            targetDescriptor: NSAppleEventDescriptor(bundleIdentifier: bundleID), returnID: -1, transactionID: 0)
        event.setParam(specifier, forKeyword: code("----"))
        let reply: NSAppleEventDescriptor
        do {
            reply = try event.sendEvent(options: [.waitForReply, .canInteract], timeout: 5)
        } catch let error as NSError {
            if error.code == -1743 { throw denied }
            return []
        }
        try Task.checkCancellation()
        if let status = reply.paramDescriptor(forKeyword: code("errn"))?.int32Value, status != 0 {
            if status == -1743 { throw denied }
            return []
        }
        guard let answer = reply.paramDescriptor(forKeyword: code("----")) else { return [] }
        guard answer.descriptorType == code("list") else { return [answer] }
        return answer.numberOfItems > 0 ? (1...answer.numberOfItems).compactMap { answer.atIndex($0) } : []
    }

    private static func code(_ text: String) -> UInt32 {
        text.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }
}

/// Reads a window's `AXDocument`, 1 s per call.
private nonisolated enum CopyPathAccessibility {
    @concurrent
    static func document(pid: Int32) async throws -> String? {
        guard AXIsProcessTrusted() else { throw CopyPathFailure.accessibility }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            try Task.checkCancellation()
            var window: CFTypeRef?
            let read = AXUIElementCopyAttributeValue(app, attribute as CFString, &window)
            if read == .apiDisabled { throw CopyPathFailure.accessibility }
            guard read == .success, let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { continue }
            var document: CFTypeRef?
            let element = unsafeDowncast(window, to: AXUIElement.self)
            guard AXUIElementCopyAttributeValue(element, kAXDocumentAttribute as CFString, &document) == .success,
                let text = document as? String, !text.isEmpty else { continue }
            return text
        }
        return nil
    }
}
