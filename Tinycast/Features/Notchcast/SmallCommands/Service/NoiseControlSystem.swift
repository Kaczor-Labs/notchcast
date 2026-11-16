import AppKit
import ApplicationServices

nonisolated enum NoiseControlSystem {
    private struct Button {
        let element: AXUIElement
        let value: NoiseControlEngine.Button
    }

    enum Failure: Error { case unavailable }

    /// Control Center shows a window only while one of its menus is open; each is searched alone.
    @concurrent
    static func observe(processID: Int32, deadline: Duration) async throws -> [NoiseControlService.Window] {
        guard AXIsProcessTrusted() else { throw SmallCommandsFailure.needsAccessibility }
        try Task.checkCancellation()
        guard uptime < deadline else { throw Failure.unavailable }
        return try windows(AXUIElementCreateApplication(processID)).map {
            .init(handle: .init(element: $0), buttons: try buttons(in: $0, deadline: deadline).map(\.value))
        }
    }

    @concurrent
    static func perform(_ action: NoiseControlService.Action, processID: Int32, deadline: Duration) async throws {
        guard AXIsProcessTrusted() else { throw SmallCommandsFailure.needsAccessibility }
        try Task.checkCancellation()
        guard uptime < deadline else { throw Failure.unavailable }
        let root = AXUIElementCreateApplication(processID)
        switch action {
        case .toggleMenu:
            guard let barValue = attribute(root, "AXExtrasMenuBar"),
                CFGetTypeID(barValue) == AXUIElementGetTypeID() else { throw Failure.unavailable }
            let bar = unsafeDowncast(barValue, to: AXUIElement.self)
            guard let sound = children(bar).first(where: {
                attribute($0, kAXIdentifierAttribute) as? String == "com.apple.menuextra.sound"
            }) else { throw Failure.unavailable }
            guard uptime < deadline, AXUIElementPerformAction(sound, kAXPressAction as CFString) == .success else {
                throw Failure.unavailable
            }
        case .press(let mode, let handle):
            guard let window = try windows(root).first(where: { CFEqual($0, handle.element) }) else {
                throw Failure.unavailable
            }
            let found = try buttons(in: window, deadline: deadline)
            try Task.checkCancellation()
            guard uptime < deadline, let button = found.first(where: { $0.value.mode == mode }),
                AXUIElementPerformAction(button.element, kAXPressAction as CFString) == .success else {
                throw Failure.unavailable
            }
        }
    }

    private static var uptime: Duration { .seconds(ProcessInfo.processInfo.systemUptime) }

    /// Only a successful read says what is open; any AX error must never pass for a closed menu.
    private static func windows(_ root: AXUIElement) throws -> [AXUIElement] {
        AXUIElementSetMessagingTimeout(root, 0.1)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &value) == .success,
            let windows = value as? [AXUIElement] else { throw SmallCommandsFailure.controlCenterUnresponsive }
        return windows
    }

    private static func buttons(in window: AXUIElement, deadline: Duration) throws -> [Button] {
        var found: [Button] = []
        var remaining = [(window, 0)]
        var visited = 0
        while let (element, depth) = remaining.popLast(), visited < 512 {
            try Task.checkCancellation()
            guard uptime < deadline else { throw Failure.unavailable }
            visited += 1
            let names = [kAXTitleAttribute, kAXDescriptionAttribute, kAXIdentifierAttribute].compactMap {
                attribute(element, $0) as? String
            }
            if let mode = NoiseControlEngine.Mode.allCases.first(where: { names.contains($0.rawValue) }) {
                let value = (attribute(element, kAXValueAttribute) as? NSNumber)?.boolValue
                    ?? (attribute(element, kAXSelectedAttribute) as? NSNumber)?.boolValue
                found.append(Button(element: element, value: .init(mode: mode, selected: value)))
            }
            if depth < 8 { remaining += children(element).map { ($0, depth + 1) } }
        }
        return found
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(element, 0.1)
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
}
