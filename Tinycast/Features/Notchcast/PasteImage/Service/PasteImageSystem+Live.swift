import AppKit
import Carbon.HIToolbox
import ImageIO
import UniformTypeIdentifiers

extension PasteImageSystem {
    static let live = PasteImageSystem(
        frontFinder: {
            guard let app = NSWorkspace.shared.frontmostApplication,
                  app.bundleIdentifier == PasteImagePolicy.finderBundleIdentifier
            else { return nil }
            return app.processIdentifier
        },
        commandCharacter: { ASCIIKeyboardLayout.character(for: $0, modifiers: UInt32(cmdKey >> 8)) },
        clipboardTypes: { NSPasteboard.general.types?.map(\.rawValue) ?? [] },
        clipboardImage: {
            let board = NSPasteboard.general
            guard PasteImagePolicy.accepts(types: board.types?.map(\.rawValue) ?? []) else { return nil }
            for type in PasteImagePolicy.imageTypes {
                if let data = board.data(forType: NSPasteboard.PasteboardType(type)) {
                    return PasteImageClip(data: data, isPNG: type == UTType.png.identifier)
                }
            }
            return nil
        },
        focusedRole: { await PasteImageFinder.focusedRole(of: $0) },
        save: { await PasteImageFinder.save($0, at: $1) },
        replay: { pid, keyCode in
            let source = CGEventSource(stateID: .combinedSessionState)
            let events = [true, false].compactMap {
                CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: $0)
            }
            for event in events {
                event.flags = .maskCommand
                event.setIntegerValueField(.eventSourceUserData, value: Paster.tinycastEventTag)
                event.postToPid(pid)
            }
        }
    )
}

/// Finder's focus over Accessibility, the PNG conversion and Finder's move, all off the main actor.
private nonisolated enum PasteImageFinder {
    /// -48 and -15267 are Finder's "an item with that name already exists".
    private static let nameTakenCodes: Set<Int> = [-48, -15267]

    private static let files = PasteImageFiles(
        makeFolder: {
            let folder = FileManager.default.temporaryDirectory
                .appending(path: "Notchcast Paste \(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(
                at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            return folder
        },
        write: { try $0.write(to: $1, options: .withoutOverwriting) },
        remove: { try? FileManager.default.removeItem(at: $0) })

    @concurrent
    static func focusedRole(of pid: Int32) async -> String? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        let element = unsafeDowncast(focused, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, 1)
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        return role as? String
    }

    @concurrent
    static func save(_ clip: PasteImageClip, at date: Date) async -> Bool {
        guard let png = clip.isPNG ? clip.data : png(from: clip.data) else { return false }
        return PasteImageSaver.save(png, at: date, files: files, place: place)
    }

    /// Copies the source's own properties too, so a JPEG or HEIC keeps its orientation.
    private static func png(from data: Data) -> Data? {
        let output = NSMutableData()
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
              let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImageFromSource(destination, source, 0, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    /// `move file to insertion location`, then `select` the moved item, as Finder's own paste leaves it.
    private static func place(_ file: URL) -> PasteImagePlacement {
        let finder = NSAppleEventDescriptor(bundleIdentifier: PasteImagePolicy.finderBundleIdentifier)
        let move = event("core", "move", to: finder, directObject: NSAppleEventDescriptor(fileURL: file))
        move.setParam(insertionLocation(), forKeyword: code("insh"))
        let (reply, status) = send(move)
        guard status == 0 else { return nameTakenCodes.contains(status) ? .nameTaken : .failed }
        if let moved = reply?.paramDescriptor(forKeyword: code("----")) {
            _ = send(event("misc", "slct", to: finder, directObject: moved))
        }
        return .placed
    }

    /// The front Finder window's folder, or the Desktop when no window is open.
    private static func insertionLocation() -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(typeCode: code("prop")), forKeyword: code("want"))
        record.setDescriptor(.null(), forKeyword: code("from"))
        record.setDescriptor(NSAppleEventDescriptor(enumCode: code("prop")), forKeyword: code("form"))
        record.setDescriptor(NSAppleEventDescriptor(typeCode: code("pins")), forKeyword: code("seld"))
        return record.coerce(toDescriptorType: code("obj ")) ?? record
    }

    private static func event(
        _ eventClass: String, _ eventID: String, to target: NSAppleEventDescriptor,
        directObject: NSAppleEventDescriptor
    ) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(
            eventClass: code(eventClass), eventID: code(eventID), targetDescriptor: target,
            returnID: -1, transactionID: 0)
        event.setParam(directObject, forKeyword: code("----"))
        return event
    }

    /// `canInteract` lets macOS ask for Automation; the wait is capped at the policy's 30 s.
    private static func send(_ event: NSAppleEventDescriptor) -> (reply: NSAppleEventDescriptor?, status: Int) {
        do {
            let reply = try event.sendEvent(options: [.waitForReply, .canInteract], timeout: PasteImagePolicy.timeout)
            return (reply, Int(reply.paramDescriptor(forKeyword: code("errn"))?.int32Value ?? 0))
        } catch {
            return (nil, (error as NSError).code)
        }
    }

    private static func code(_ text: String) -> OSType {
        text.utf8.reduce(0) { ($0 << 8) | OSType($1) }
    }
}
