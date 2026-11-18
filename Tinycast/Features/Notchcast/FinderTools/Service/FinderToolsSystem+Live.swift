import AppKit
import ApplicationServices
import Carbon.HIToolbox

extension FinderToolsSystem {
    static let finderBundleID = "com.apple.finder"

    static let live = FinderToolsSystem(
        syntheticTag: Paster.tinycastEventTag,
        frontmostFinderPID: {
            guard let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier == finderBundleID
            else { return nil }
            return app.processIdentifier
        },
        changeCount: { NSPasteboard.general.changeCount },
        commandCharacter: { ASCIIKeyboardLayout.character(for: $0, modifiers: UInt32(cmdKey >> 8)) },
        focus: { await focusChain(pid: $0) },
        post: { pid, keyCode, modifiers in
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down)
                else { continue }
                event.flags = flags(modifiers)
                event.setIntegerValueField(.eventSourceUserData, value: Paster.tinycastEventTag)
                event.postToPid(pid)
            }
        }
    )

    private static func flags(_ modifiers: FinderToolsPolicy.Modifiers) -> CGEventFlags {
        let pairs: [(FinderToolsPolicy.Modifiers, CGEventFlags)] = [
            (.command, .maskCommand), (.shift, .maskShift), (.option, .maskAlternate), (.control, .maskControl),
        ]
        return pairs.reduce(into: []) { if modifiers.contains($1.0) { $0.insert($1.1) } }
    }

    @concurrent
    private static func focusChain(pid: Int32) async -> [FinderToolsFocus.Element]? {
        guard var element = element(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute)
        else { return nil }
        var chain: [FinderToolsFocus.Element] = []
        for _ in 0..<16 {
            guard let role = attribute(element, kAXRoleAttribute) as? String else { break }
            chain.append(.init(role: role, subrole: attribute(element, kAXSubroleAttribute) as? String))
            guard role != kAXWindowRole, role != "AXSheet", let parent = self.element(element, kAXParentAttribute)
            else { break }
            element = parent
        }
        return chain
    }

    private static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        AXUIElementSetMessagingTimeout(element, 0.25)
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
}
