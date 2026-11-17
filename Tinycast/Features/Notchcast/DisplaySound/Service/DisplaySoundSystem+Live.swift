import AppKit
import AudioToolbox
import CoreAudio
import Darwin
import IOKit
import Synchronization

extension DisplaySoundSystem {
    static let live = DisplaySoundSystem(
        displays: .init(
            online: {
                var count: UInt32 = 0
                guard CGGetOnlineDisplayList(0, nil, &count) == .success else { return nil }
                var ids = [UInt32](repeating: 0, count: Int(count))
                guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return nil }
                return Array(ids.prefix(Int(count)))
            },
            uuid: { display in
                guard let uuid = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue(),
                      let text = CFUUIDCreateString(nil, uuid) else { return nil }
                return text as String
            },
            isActive: { CGDisplayIsActive($0) != 0 && CGDisplayIsAsleep($0) == 0 },
            isBuiltIn: { CGDisplayIsBuiltin($0) != 0 },
            readSystem: SystemBrightness.read,
            writeSystem: SystemBrightness.write,
            discoverDDC: IOAVLink.discover,
            readGamma: { display in
                let capacity = CGDisplayGammaTableCapacity(display)
                guard capacity > 0 else { return nil }
                var red = [Float](repeating: 0, count: Int(capacity))
                var green = red
                var blue = red
                var count: UInt32 = 0
                guard CGGetDisplayTransferByTable(display, capacity, &red, &green, &blue, &count) == .success,
                      count > 0 else { return nil }
                let length = Int(count)
                return BrightnessGamma(red: Array(red.prefix(length)), green: Array(green.prefix(length)),
                                       blue: Array(blue.prefix(length)))
            },
            writeGamma: { display, gamma in
                CGSetDisplayTransferByTable(display, UInt32(gamma.red.count), gamma.red, gamma.green, gamma.blue)
                    == .success
            }),
        audio: .init(
            defaultOutput: CoreAudioLevels.defaultOutput,
            has: { device, control in
                var address = CoreAudioLevels.address(control)
                return AudioObjectHasProperty(device, &address)
            },
            stereoChannels: { device in
                var address = CoreAudioLevels.address(kAudioDevicePropertyPreferredChannelsForStereo)
                var channels: [UInt32] = [1, 2]
                var size = UInt32(2 * MemoryLayout<UInt32>.size)
                guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &channels) == noErr else { return nil }
                return channels
            },
            volume: { device, control in
                var address = CoreAudioLevels.address(control)
                var value: Float32 = 0
                var size = UInt32(MemoryLayout.size(ofValue: value))
                guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr,
                      value.isFinite, (0...1).contains(value) else { return nil }
                return Double(value)
            },
            canSetVolume: { CoreAudioLevels.isSettable($0, CoreAudioLevels.address($1)) },
            setVolume: { device, control, volume in
                var address = CoreAudioLevels.address(control)
                var value = Float32(volume)
                return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout.size(ofValue: value)),
                                                  &value) == noErr
            },
            muted: { device in
                var address = CoreAudioLevels.address(kAudioDevicePropertyMute)
                var value: UInt32 = 0
                var size = UInt32(MemoryLayout.size(ofValue: value))
                guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
                return value != 0
            },
            canSetMute: { CoreAudioLevels.isSettable($0, CoreAudioLevels.address(kAudioDevicePropertyMute)) },
            setMuted: { device, muted in
                var address = CoreAudioLevels.address(kAudioDevicePropertyMute)
                var value = UInt32(muted ? 1 : 0)
                return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout.size(ofValue: value)),
                                                  &value) == noErr
            }),
        sleep: { try await Task.sleep(for: $0) },
        screenNames: {
            Dictionary(NSScreen.screens.compactMap { screen -> (UInt32, String)? in
                guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
                else { return nil }
                return (number.uint32Value, screen.localizedName)
            }, uniquingKeysWith: { first, _ in first })
        },
        displayContaining: { location, displays in
            displays.first { CGDisplayBounds($0).contains(location) }
        },
        functionKeysAdjustBrightness: {
            BrightnessFunctionKeys.functionKeysAdjustBrightness(symbolicHotKeys: CFPreferencesCopyAppValue(
                "AppleSymbolicHotKeys" as CFString, "com.apple.symbolichotkeys" as CFString) as? [String: Any])
        },
        replay: { key, modifiers in
            for state in [0xA, 0xB] {
                guard let event = NSEvent.otherEvent(
                    with: .systemDefined, location: .zero,
                    modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(modifiers)), timestamp: 0,
                    windowNumber: 0, context: nil, subtype: 8,
                    data1: (key.rawValue << 16) | (state << 8), data2: -1)?.cgEvent else { continue }
                event.setIntegerValueField(.eventSourceUserData, value: Paster.tinycastEventTag)
                event.post(tap: .cghidEventTap)
            }
        },
        watchDisplays: { changed in
            [
                NotificationToken(NotificationCenter.default.addObserver(
                    forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
                ) { _ in MainActor.assumeIsolated { changed(false) } }, center: .default),
                NotificationToken(NSWorkspace.shared.notificationCenter.addObserver(
                    forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
                ) { _ in MainActor.assumeIsolated { changed(true) } }, center: NSWorkspace.shared.notificationCenter),
            ]
        },
        watchAudio: { output, changed in
            let block: AudioObjectPropertyListenerBlock = { _, _ in
                Task { @MainActor in changed() }
            }
            var addresses = [(AudioObjectID(kAudioObjectSystemObject),
                              CoreAudioLevels.address(kAudioHardwarePropertyDefaultOutputDevice,
                                                      scope: kAudioObjectPropertyScopeGlobal))]
            if let output {
                addresses += [
                    (output, CoreAudioLevels.address(.virtualMain)),
                    (output, CoreAudioLevels.address(kAudioDevicePropertyVolumeScalar,
                                                     element: kAudioObjectPropertyElementWildcard)),
                    (output, CoreAudioLevels.address(kAudioDevicePropertyMute)),
                ]
            }
            return addresses.compactMap { CoreAudioListener(device: $0.0, address: $0.1, block: block) }
        }
    )
}

private enum SystemBrightness {
    private typealias Get = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias Set = @convention(c) (UInt32, Float) -> Int32

    private struct Calls: Sendable {
        let get: Get
        let set: Set
    }

    private static let calls: Calls? = {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
            let get = dlsym(handle, "DisplayServicesGetBrightness"),
            let set = dlsym(handle, "DisplayServicesSetBrightness") else { return nil }
        return Calls(get: unsafeBitCast(get, to: Get.self), set: unsafeBitCast(set, to: Set.self))
    }()

    @Sendable static func read(_ display: UInt32) -> Double? {
        var value: Float = 0
        guard let calls, calls.get(display, &value) == 0, value.isFinite, (0...1).contains(value) else { return nil }
        return Double(value)
    }

    @Sendable static func write(_ display: UInt32, _ value: Double) -> Bool {
        calls?.set(display, Float(value)) == 0
    }
}

/// A monitor's IOAVService; MCCS wants 50 ms between commands and before reading a reply.
private final class IOAVLink: Sendable {
    private typealias Create = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    private typealias Transfer = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32)
        -> IOReturn

    private struct Calls: Sendable {
        let create: Create
        let write: Transfer
        let read: Transfer
    }

    private struct Service: @unchecked Sendable {
        let reference: CFTypeRef
    }

    private static let calls: Calls? = {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY),
              let create = dlsym(handle, "IOAVServiceCreateWithService"),
              let write = dlsym(handle, "IOAVServiceWriteI2C"),
              let read = dlsym(handle, "IOAVServiceReadI2C") else { return nil }
        return Calls(create: unsafeBitCast(create, to: Create.self),
                     write: unsafeBitCast(write, to: Transfer.self), read: unsafeBitCast(read, to: Transfer.self))
    }()

    private static let gap = Duration.milliseconds(50)
    private let service: Service
    private let lastCommand = Mutex<ContinuousClock.Instant?>(nil)

    private init(_ service: CFTypeRef) { self.service = Service(reference: service) }

    private func send(_ packet: [UInt8]) -> Bool {
        guard let calls = Self.calls else { return false }
        return lastCommand.withLock { last in
            if let last, last.duration(to: .now) < Self.gap { Thread.sleep(until: last + Self.gap) }
            defer { last = .now }
            var packet = packet
            return packet.withUnsafeMutableBytes { buffer in
                calls.write(service.reference, BrightnessDDC.chip, BrightnessDDC.host, buffer.baseAddress!,
                            UInt32(buffer.count)) == kIOReturnSuccess
            }
        }
    }

    private func receive(_ length: Int) -> [UInt8]? {
        guard let calls = Self.calls else { return nil }
        return lastCommand.withLock { last in
            if let last { Thread.sleep(until: last + Self.gap) }
            defer { last = .now }
            var reply = [UInt8](repeating: 0, count: length)
            let result = reply.withUnsafeMutableBytes { buffer in
                calls.read(service.reference, BrightnessDDC.chip, BrightnessDDC.host, buffer.baseAddress!,
                           UInt32(buffer.count))
            }
            return result == kIOReturnSuccess ? reply : nil
        }
    }

    @Sendable static func discover() -> [String: BrightnessDDCLink] {
        guard let calls else { return [:] }
        var iterator: io_iterator_t = 0
        guard IORegistryCreateIterator(kIOMainPortDefault, kIOServicePlane,
                                      IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS
        else { return [:] }
        defer { IOObjectRelease(iterator) }
        var links: [String: BrightnessDDCLink] = [:]
        var uuid: String?
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            var name = [CChar](repeating: 0, count: 128)
            IORegistryEntryGetName(entry, &name)
            let end = name.firstIndex(of: 0) ?? name.endIndex
            let label = String(bytes: name[..<end].map { UInt8(bitPattern: $0) }, encoding: .utf8)
            if label == "AppleCLCD2" || label == "IOMobileFramebufferShim" {
                uuid = property(entry, "EDID UUID")
            } else if label == "DCPAVServiceProxy" {
                if let uuid, property(entry, "Location") == "External",
                   let service = calls.create(kCFAllocatorDefault, entry)?.takeRetainedValue() {
                    let link = IOAVLink(service)
                    links[uuid.uppercased()] = BrightnessDDCLink(send: link.send, receive: link.receive)
                }
                uuid = nil
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return links
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> String? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
    }
}

private extension Thread {
    static func sleep(until instant: ContinuousClock.Instant) {
        let remaining = ContinuousClock.now.duration(to: instant)
        guard remaining > .zero else { return }
        let (seconds, attoseconds) = remaining.components
        sleep(forTimeInterval: Double(seconds) + Double(attoseconds) / 1e18)
    }
}

private enum CoreAudioLevels {
    static func address(_ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput,
                        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain)
        -> AudioObjectPropertyAddress {
        .init(mSelector: selector, mScope: scope, mElement: element)
    }

    static func address(_ control: AudioVolumeControl) -> AudioObjectPropertyAddress {
        switch control {
        case .virtualMain: address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        case .main: address(kAudioDevicePropertyVolumeScalar)
        case let .channel(channel): address(kAudioDevicePropertyVolumeScalar, element: channel)
        }
    }

    @Sendable static func defaultOutput() -> UInt32? {
        var address = address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout.size(ofValue: device))
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
            == noErr, device != kAudioObjectUnknown else { return nil }
        return device
    }

    static func isSettable(_ device: UInt32, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        var settable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }
}

/// Removes its CoreAudio listener when released, so the module's teardown is dropping the array.
private final class CoreAudioListener {
    private let device: AudioObjectID
    private var address: AudioObjectPropertyAddress
    private let block: AudioObjectPropertyListenerBlock

    init?(device: AudioObjectID, address: AudioObjectPropertyAddress, block: @escaping AudioObjectPropertyListenerBlock) {
        var address = address
        guard address.mElement == kAudioObjectPropertyElementWildcard || AudioObjectHasProperty(device, &address),
              AudioObjectAddPropertyListenerBlock(device, &address, .main, block) == noErr else { return nil }
        self.device = device
        self.address = address
        self.block = block
    }

    deinit { AudioObjectRemovePropertyListenerBlock(device, &address, .main, block) }
}
