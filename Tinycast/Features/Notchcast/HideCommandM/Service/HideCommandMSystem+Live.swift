import AppKit
import Carbon.HIToolbox

extension HideCommandMSystem {
    static let live = HideCommandMSystem(
        ownPID: ProcessInfo.processInfo.processIdentifier,
        frontmost: {
            NSWorkspace.shared.frontmostApplication.map {
                HideCommandMTarget(
                    processIdentifier: $0.processIdentifier, bundleIdentifier: $0.bundleIdentifier,
                    canHide: $0.activationPolicy == .regular)
            }
        },
        commandCharacter: { ASCIIKeyboardLayout.character(for: $0, modifiers: UInt32(cmdKey >> 8)) },
        hasWindows: { pid in
            let windows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
            return windows.contains {
                ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
            }
        },
        hide: { pid in NSRunningApplication(processIdentifier: pid)?.hide() ?? false },
        replay: { pid, keyCode in
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: down)
                else { continue }
                event.flags = .maskCommand
                event.setIntegerValueField(.eventSourceUserData, value: Paster.tinycastEventTag)
                event.postToPid(pid)
            }
        }
    )
}
