// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint faada18d's Finder cut and paste: ask Finder where, then write the PNG there.

import AppKit
import Carbon.HIToolbox
import ImageIO
import OSLog
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
            guard let type = PasteImagePolicy.imageType(in: board.types?.map(\.rawValue) ?? []),
                  let data = board.data(forType: NSPasteboard.PasteboardType(type))
            else { return nil }
            return PasteImageClip(data: data, isPNG: type == PasteImagePolicy.pngType)
        },
        focus: { await PasteImageFinder.focus() },
        save: { await PasteImageFinder.save($0, at: $1) },
        replay: { keyCode in
            let source = CGEventSource(stateID: .combinedSessionState)
            let events = [true, false].compactMap {
                CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: $0)
            }
            for event in events {
                event.flags = .maskCommand
                event.setIntegerValueField(.eventSourceUserData, value: Paster.tinycastEventTag)
                event.post(tap: .cgSessionEventTap)
            }
        },
        openAutomationSettings: {
            guard let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
            else { return }
            NSWorkspace.shared.open(url)
        }
    )
}

/// Finder's focus, the PNG conversion, Finder's answers and the write, all off the main actor.
private nonisolated enum PasteImageFinder {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Notchcast", category: "PasteImage")

    private static let files = PasteImageFiles(
        write: { try $0.write(to: $1, options: .withoutOverwriting) },
        remove: { try? FileManager.default.removeItem(at: $0) })

    @concurrent
    static func focus() async -> PasteImageFocus? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 1)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        let element = unsafeDowncast(focused, to: AXUIElement.self)
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        AXUIElementSetMessagingTimeout(element, 1)
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        return PasteImageFocus(pid: pid, role: role as? String)
    }

    @concurrent
    static func save(_ clip: PasteImageClip, at date: Date) async -> PasteImageFailure? {
        if let failure = checkFrontWindow() { return failure }
        guard clip.data.count <= PasteImagePolicy.maxImageBytes else {
            return fail(.tooLarge, step: "image", "\(clip.data.count) bytes copied")
        }
        guard let png = png(from: clip) else { return fail(.unreadable, step: "image", "does not decode") }
        guard png.count <= PasteImagePolicy.maxImageBytes else {
            return fail(.tooLarge, step: "image", "\(png.count) bytes as PNG")
        }
        let location = send(get(property("pURL", of: property("pins"))))
        guard location.status == 0 else {
            return fail(.finder(status: location.status), step: "location", "status \(location.status)")
        }
        guard let folder = url(location.reply), PasteImagePolicy.accepts(frontFolder: folder, hasWindow: true) else {
            return fail(.noFolder, step: "location", "not a folder")
        }
        switch PasteImageSaver.save(png, into: folder, at: date, timeZone: .current, files: files) {
        case let .failed(code):
            return fail(.notSaved, step: "write", "error \(code)")
        case let .saved(file):
            let select = send(event("misc", "slct", to: finder, directObject: NSAppleEventDescriptor(fileURL: file)))
            if select.status != 0 {
                logger.error("select failed: status \(select.status, privacy: .public), file kept")
            }
            return nil
        }
    }

    private static func fail(_ failure: PasteImageFailure, step: String, _ detail: String) -> PasteImageFailure {
        logger.error("\(step, privacy: .public) failed: \(detail, privacy: .public)")
        return failure
    }

    /// A PNG is kept once it decodes; anything else copies its properties too, so it keeps its orientation.
    private static func png(from clip: PasteImageClip) -> Data? {
        guard let source = CGImageSourceCreateWithData(clip.data as CFData, nil), CGImageSourceGetCount(source) > 0
        else { return nil }
        if clip.isPNG {
            let decoded = CGImageSourceCreateImageAtIndex(
                source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
            return decoded == nil ? nil : clip.data
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImageFromSource(destination, source, 0, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    /// Asks Finder for `URL of target of Finder window 1`, and whether that window exists when it has none.
    private static func checkFrontWindow() -> PasteImageFailure? {
        let window = specifier("brow", "indx", NSAppleEventDescriptor(int32: 1))
        let target = send(get(property("pURL", of: property("fvtg", of: window))))
        if target.status == 0, let folder = url(target.reply) {
            guard PasteImagePolicy.accepts(frontFolder: folder, hasWindow: true) else {
                return fail(.noFolder, step: "target", "not a folder")
            }
            return nil
        }
        guard PasteImageFailure.meansNoFolder(status: target.status) else {
            return fail(.finder(status: target.status), step: "target", "status \(target.status)")
        }
        let exists = send(event("core", "doex", to: finder, directObject: window))
        guard exists.status == 0, let hasWindow = result(exists.reply)?.booleanValue else {
            return fail(.finder(status: exists.status), step: "target", "status \(exists.status)")
        }
        guard PasteImagePolicy.accepts(frontFolder: nil, hasWindow: hasWindow) else {
            return fail(.noFolder, step: "target", "window without a folder, status \(target.status)")
        }
        return nil
    }

    private static var finder: NSAppleEventDescriptor {
        NSAppleEventDescriptor(bundleIdentifier: PasteImagePolicy.finderBundleIdentifier)
    }

    private static func get(_ object: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        event("core", "getd", to: finder, directObject: object)
    }

    private static func result(_ reply: NSAppleEventDescriptor?) -> NSAppleEventDescriptor? {
        reply?.paramDescriptor(forKeyword: code("----"))
    }

    private static func url(_ reply: NSAppleEventDescriptor?) -> URL? {
        result(reply)?.stringValue.flatMap(URL.init(string:))
    }

    /// `pins` is the insertion location: the front window's folder, or the Desktop when no window is open.
    private static func property(_ name: String, of owner: NSAppleEventDescriptor = .null()) -> NSAppleEventDescriptor {
        specifier("prop", "prop", NSAppleEventDescriptor(typeCode: code(name)), from: owner)
    }

    private static func specifier(
        _ want: String, _ form: String, _ selector: NSAppleEventDescriptor, from owner: NSAppleEventDescriptor = .null()
    ) -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(typeCode: code(want)), forKeyword: code("want"))
        record.setDescriptor(owner, forKeyword: code("from"))
        record.setDescriptor(NSAppleEventDescriptor(enumCode: code(form)), forKeyword: code("form"))
        record.setDescriptor(selector, forKeyword: code("seld"))
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
