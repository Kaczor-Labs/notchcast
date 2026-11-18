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
    private static let system = AudioObjectID(kAudioObjectSystemObject)
    private var address: AudioObjectPropertyAddress
    private let block: AudioObjectPropertyListenerBlock

    init?(_ address: AudioObjectPropertyAddress, block: @escaping AudioObjectPropertyListenerBlock) {
        var address = address
        guard AudioObjectAddPropertyListenerBlock(Self.system, &address, .main, block) == noErr else { return nil }
        self.address = address
        self.block = block
    }

    deinit { AudioObjectRemovePropertyListenerBlock(Self.system, &address, .main, block) }
}

/// Control Center's Sound menu via the public Accessibility API, each element under a short timeout.
private enum NoiseControlMenu {
    static let controlCenter = "com.apple.controlcenter"
    static let soundExtra = "com.apple.menuextra.sound"
    static let callTimeout: Float = 0.2

    static var uptime: Duration { .seconds(ProcessInfo.processInfo.systemUptime) }

    /// A timeout set on one element covers only that element, so the tree prepares each one it reads.
    static var tree: NoiseControlMenuTree<AXUIElement> {
        NoiseControlMenuTree(
            prepare: { AXUIElementSetMessagingTimeout($0, callTimeout) },
            children: { elements($0, kAXChildrenAttribute) },
            identifier: { value($0, kAXIdentifierAttribute) as? String },
            labels: { element in [kAXTitleAttribute, kAXDescriptionAttribute].compactMap { value(element, $0) as? String } },
            canPress: canPress,
            selected: { element in
                let flag = value(element, kAXValueAttribute) as? NSNumber ?? value(element, kAXSelectedAttribute) as? NSNumber
                return flag?.boolValue
            },
            now: { uptime })
    }

    @concurrent
    static func perform(_ step: NoiseControlSwitcher.Step, deadline: Duration) async throws -> [NoiseControlButton] {
        let pid = await MainActor.run {
            NSRunningApplication.runningApplications(withBundleIdentifier: controlCenter).first?.processIdentifier
        }
        guard let pid else { throw NoiseControlFailure.menuUnavailable }
        let app = AXUIElementCreateApplication(pid)
        tree.prepare(app)
        switch step {
        case .open:
            guard let extra = soundExtra(in: app, deadline: deadline), press(extra) else {
                throw NoiseControlFailure.menuUnavailable
            }
        case .close(let sawModes):
            guard let extra = soundExtra(in: app, deadline: deadline),
                  tree.soundMenuOpen(windows: elements(app, kAXWindowsAttribute), sawModes: sawModes, deadline: deadline)
            else { break }
            _ = press(extra)
        case .read:
            return tree.items(in: elements(app, kAXWindowsAttribute), deadline: deadline).map(\.button)
        case .press(let mode):
            let items = tree.items(in: elements(app, kAXWindowsAttribute), deadline: deadline)
            guard let item = items.first(where: { $0.button.mode == mode }), press(item.element) else {
                throw NoiseControlFailure.timedOut
            }
        }
        return []
    }

    private static func soundExtra(in app: AXUIElement, deadline: Duration) -> AXUIElement? {
        guard uptime < deadline, let bar = value(app, "AXExtrasMenuBar"), CFGetTypeID(bar) == AXUIElementGetTypeID()
        else { return nil }
        let menuBar = unsafeDowncast(bar, to: AXUIElement.self)
        tree.prepare(menuBar)
        return tree.first(identifier: soundExtra, in: elements(menuBar, kAXChildrenAttribute), deadline: deadline)
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
