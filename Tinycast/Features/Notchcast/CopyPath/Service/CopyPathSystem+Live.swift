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

/// Reads `AXDocument` or a Gecko page's `AXURL`; each read's timeout is per element.
nonisolated enum CopyPathAccessibility {
    static let timeout: Float = 1
    /// Both page walks and the wait between them; an empty tab walks it all.
    static let pageBudget = Duration.seconds(2)
    static let firstActivationWait = Duration.milliseconds(500)
    /// A second walk with less than this left would only end on the budget.
    static let secondWalkMinimum = Duration.milliseconds(200)

    /// A window's elements walked before giving up; a long tab sidebar alone holds hundreds.
    static let maxElements = 2000

    /// A walk out of budget: it ends as if nothing were there, never as Unavailable.
    struct BudgetSpent: Error {}

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
        let deadline = ContinuousClock.now + pageBudget
        let app = AXUIElementCreateApplication(pid)
        // Gecko builds its tree only once a client asks the application for its role.
        _ = try read(app, kAXRoleAttribute)
        if let address = try pageAddress(app, deadline: deadline) { return address }
        // On first activation the pages arrive from Gecko's content processes a moment later.
        guard ContinuousClock.now + firstActivationWait + secondWalkMinimum < deadline else { return nil }
        try await Task.sleep(for: firstActivationWait)
        return try pageAddress(app, deadline: deadline)
    }

    /// Nil once `deadline` passes, as if no page were there, so a slow walk still ends the run.
    private static func pageAddress(_ app: AXUIElement, deadline: ContinuousClock.Instant) throws -> String? {
        func element(_ of: AXUIElement, _ attribute: String) throws -> AXUIElement? {
            try leashed(deadline, cap: timeout) { try self.element(of, attribute, timeout: $0) }
        }
        do {
            var focus = try element(app, kAXFocusedUIElementAttribute)
            for _ in 0..<maxElements {
                guard let current = focus else { break }
                if let address = try address(current, deadline: deadline) { return address }
                focus = try element(current, kAXParentAttribute)
            }
            guard let window = try element(app, kAXFocusedWindowAttribute) else { return nil }
            var queue = [window]
            var index = 0
            while index < queue.count, index < maxElements {
                if let address = try address(queue[index], deadline: deadline) { return address }
                queue += try leashed(deadline, cap: timeout) { try children(queue[index], timeout: $0) }
                index += 1
            }
            return nil
        } catch is BudgetSpent {
            return nil
        }
    }

    /// A page's `AXURL`; Gecko's window and panels are `chrome:` or `moz-extension:` web areas too.
    private static func address(_ element: AXUIElement, deadline: ContinuousClock.Instant) throws -> String? {
        func value(_ attribute: String) throws -> CFTypeRef? {
            try leashed(deadline, cap: timeout) { try read(element, attribute, timeout: $0) }
        }
        guard try value(kAXRoleAttribute) as? String == "AXWebArea",
            let url = try value(kAXURLAttribute) as? URL,
            ["http", "https", "file"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url.absoluteString
    }

    /// The AX timeout for the next read: at most `cap`, never past `deadline`; nil when nearly out.
    static func leash(_ deadline: ContinuousClock.Instant, cap: Float) -> Float? {
        CopyPathBudget.timeout(left: ContinuousClock.now.duration(to: deadline), cap: cap)
    }

    /// One read leashed afresh; a clipped read that times out spent the budget rather than hung.
    static func leashed<T>(_ deadline: ContinuousClock.Instant, cap: Float, _ read: (Float) throws -> T) throws -> T {
        guard let timeout = leash(deadline, cap: cap) else { throw BudgetSpent() }
        do {
            return try read(timeout)
        } catch is CopyPathUnavailable where timeout < cap {
            throw BudgetSpent()
        }
    }

    static func children(_ element: AXUIElement, timeout: Float) throws -> [AXUIElement] {
        guard let value = try read(element, kAXChildrenAttribute, timeout: timeout),
            CFGetTypeID(value) == CFArrayGetTypeID() else { return [] }
        return value as? [AXUIElement] ?? []
    }

    static func element(_ element: AXUIElement, _ attribute: String, timeout: Float = timeout) throws -> AXUIElement? {
        guard let value = try read(element, attribute, timeout: timeout),
            CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    static func read(_ element: AXUIElement, _ attribute: String, timeout: Float = timeout) throws -> CFTypeRef? {
        try Task.checkCancellation()
        AXUIElementSetMessagingTimeout(element, timeout)
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return try CopyPathStatus.accessibility(status.rawValue) ? value : nil
    }
}
