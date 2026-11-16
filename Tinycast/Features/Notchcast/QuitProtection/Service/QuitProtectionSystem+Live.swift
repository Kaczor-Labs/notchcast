import AppKit
import Carbon.HIToolbox

extension QuitProtectionSystem {
    static let live = QuitProtectionSystem(
        uptime: { ProcessInfo.processInfo.systemUptime },
        frontmost: {
            guard let app = NSWorkspace.shared.frontmostApplication, let bundleID = app.bundleIdentifier
            else { return nil }
            return QuitProtectionEngine.Target(
                processIdentifier: app.processIdentifier, bundleIdentifier: bundleID,
                name: app.localizedName ?? bundleID)
        },
        commandCharacter: { ASCIIKeyboardLayout.character(for: $0, modifiers: UInt32(cmdKey >> 8)) },
        terminate: { pid in NSRunningApplication(processIdentifier: pid)?.terminate() ?? false },
        post: { pid, keyCode in
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down)
                else { continue }
                event.flags = .maskCommand
                event.setIntegerValueField(.eventSourceUserData, value: Paster.tinycastEventTag)
                event.postToPid(pid)
            }
        }
    )
}
