import AppKit
// `@preconcurrency` downgrades AX diagnostics: `kAX…` are mutable C globals, but constant.
@preconcurrency import ApplicationServices
import CoreAudio

extension NoiseControlSystem {
    static var live: Self {
        Self(
            outputModelUID: NoiseControlOutput.modelUID,
            watchOutput: NoiseControlOutput.watch,
            switcher: NoiseControlSwitcher(
                perform: { step, deadline in try await NoiseControlMenu.perform(step, deadline: deadline) },
                pause: { try await Task.sleep(for: .milliseconds(50)) },
                now: { NoiseControlMenu.uptime }))
    }
}

/// The default output device as CoreAudio reports it.
private enum NoiseControlOutput {
    static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    @MainActor
    static func modelUID() -> String? {
        var address = address(kAudioHardwarePropertyDefaultOutputDevice)
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
            == noErr, device != kAudioObjectUnknown else { return nil }
        address = Self.address(kAudioDevicePropertyModelUID)
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid) == noErr else { return nil }
        return uid?.takeRetainedValue() as String?
    }

    @MainActor
    static func watch(_ changed: @escaping @MainActor @Sendable () -> Void) -> AnyObject? {
        NoiseControlOutputListener(address(kAudioHardwarePropertyDefaultOutputDevice)) { _, _ in
            Task { @MainActor in changed() }
        }
    }
}

/// Removes its CoreAudio listener when released, so the module's teardown is dropping it.
private final class NoiseControlOutputListener {
    private let system = AudioObjectID(kAudioObjectSystemObject)
    private var address: AudioObjectPropertyAddress
    private let block: AudioObjectPropertyListenerBlock

    init?(_ address: AudioObjectPropertyAddress, block: @escaping AudioObjectPropertyListenerBlock) {
        var address = address
        guard AudioObjectAddPropertyListenerBlock(system, &address, .main, block) == noErr else { return nil }
        self.address = address
        self.block = block
    }

    deinit { AudioObjectRemovePropertyListenerBlock(system, &address, .main, block) }
}

/// Control Center's Sound menu via the public Accessibility API, each call under a short timeout.
private enum NoiseControlMenu {
    static let controlCenter = "com.apple.controlcenter"
    static let soundExtra = "com.apple.menuextra.sound"
    static let callTimeout: Float = 0.2
    static let walkLimit = 600

    static var uptime: Duration { .seconds(ProcessInfo.processInfo.systemUptime) }

    @concurrent
    static func perform(_ step: NoiseControlSwitcher.Step, deadline: Duration) async throws -> [NoiseControlButton] {
        let pid = await MainActor.run {
            NSRunningApplication.runningApplications(withBundleIdentifier: controlCenter).first?.processIdentifier
        }
        guard let pid else { throw NoiseControlFailure.menuUnavailable }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, callTimeout)
        switch step {
        case .open:
            guard let extra = soundExtra(in: app), press(extra) else { throw NoiseControlFailure.menuUnavailable }
        case .close:
            if !elements(app, kAXWindowsAttribute).isEmpty, let extra = soundExtra(in: app) { _ = press(extra) }
        case .read:
            return items(in: app, deadline: deadline).map(\.button)
        case .press(let mode):
            guard let item = items(in: app, deadline: deadline).first(where: { $0.button.mode == mode }),
                  press(item.element) else { throw NoiseControlFailure.timedOut }
        }
        return []
    }

    private struct Item {
        let element: AXUIElement
        let button: NoiseControlButton
    }

    /// The open menu's pressable mode items, first match per mode, bounded by count and deadline.
    private static func items(in app: AXUIElement, deadline: Duration) -> [Item] {
        var found: [Item] = []
        var pending = elements(app, kAXWindowsAttribute)
        var visited = 0
        while let element = pending.popLast(), visited < walkLimit, uptime < deadline {
            visited += 1
            AXUIElementSetMessagingTimeout(element, callTimeout)
            let labels = [kAXTitleAttribute, kAXDescriptionAttribute].compactMap { value(element, $0) as? String }
            if let mode = NoiseControlMode.allCases.first(where: { labels.contains($0.menuTitle) }),
               !found.contains(where: { $0.button.mode == mode }), canPress(element) {
                let flag = value(element, kAXValueAttribute) as? NSNumber ?? value(element, kAXSelectedAttribute) as? NSNumber
                let state = flag?.boolValue
                found.append(Item(element: element, button: NoiseControlButton(mode: mode, selected: state)))
            }
            pending += elements(element, kAXChildrenAttribute)
        }
        return found
    }

    private static func soundExtra(in app: AXUIElement) -> AXUIElement? {
        guard let bar = value(app, "AXExtrasMenuBar"), CFGetTypeID(bar) == AXUIElementGetTypeID() else { return nil }
        return elements(unsafeDowncast(bar, to: AXUIElement.self), kAXChildrenAttribute).first {
            value($0, kAXIdentifierAttribute) as? String == soundExtra
        }
    }

    private static func press(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    private static func canPress(_ element: AXUIElement) -> Bool {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return false }
        return (names as? [String])?.contains(kAXPressAction) == true
    }

    private static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        value(element, attribute) as? [AXUIElement] ?? []
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }
}
