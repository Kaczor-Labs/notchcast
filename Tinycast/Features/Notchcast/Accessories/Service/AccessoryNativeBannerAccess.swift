// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint faada18's NotchNativeNotificationAccess: Accessibility reads that fail loudly.

import ApplicationServices
import CoreGraphics
import Foundation

/// Notification Center through Accessibility; a timed-out or failed read throws, a missing value is nil.
struct AccessoryNativeBannerAccess: AccessoryBannerAccess {
    private enum Failure: Error { case unavailable }
    let application: AXUIElement

    func windows() throws -> [AXUIElement] {
        guard let value = try value(application, kAXWindowsAttribute) else { return [] }
        guard let windows = value as? [AXUIElement] else { throw Failure.unavailable }
        return windows
    }

    /// An unsupported attribute cannot prove the center closed, so only "no value" means closed.
    func centerIsOpen() throws -> Bool {
        guard let value = try value(application, kAXFocusedWindowAttribute, allowsUnsupported: false) else { return false }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { throw Failure.unavailable }
        return true
    }

    func string(_ element: AXUIElement, _ attribute: String) throws -> String? {
        guard let value = try value(element, attribute) else { return nil }
        guard let string = value as? String else { throw Failure.unavailable }
        return string
    }

    func children(_ element: AXUIElement) throws -> [AXUIElement] {
        guard let value = try value(element, kAXChildrenAttribute) else { return [] }
        guard let children = value as? [AXUIElement] else { throw Failure.unavailable }
        return children
    }

    /// Global coordinates, top-left origin: the space both AX positions and display bounds use.
    func frame(_ element: AXUIElement) throws -> CGRect? {
        AXUIElementSetMessagingTimeout(element, 0.1)
        var read: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &read)
        if [.invalidUIElement, .noValue, .attributeUnsupported].contains(error) { return nil }
        guard error == .success, let position = read, let size = try value(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else {
            throw Failure.unavailable
        }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &origin),
              AXValueGetValue(unsafeDowncast(size, to: AXValue.self), .cgSize, &extent) else { throw Failure.unavailable }
        return CGRect(origin: origin, size: extent)
    }

    func move(_ element: AXUIElement, to origin: CGPoint) -> Bool {
        var origin = origin
        guard let value = AXValueCreate(.cgPoint, &origin) else { return false }
        AXUIElementSetMessagingTimeout(element, 0.1)
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value) == .success
    }

    func same(_ lhs: AXUIElement, _ rhs: AXUIElement) -> Bool { CFEqual(lhs, rhs) }

    func screens() -> CGRect {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return .null }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return .null }
        return ids.prefix(Int(count)).map(CGDisplayBounds).reduce(CGRect.null) { $0.union($1) }
    }

    private func value(_ element: AXUIElement, _ attribute: String, allowsUnsupported: Bool = true) throws -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(element, 0.1)
        var result: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &result)
        if error == .noValue || (allowsUnsupported && error == .attributeUnsupported) { return nil }
        guard error == .success else { throw Failure.unavailable }
        return result
    }
}
