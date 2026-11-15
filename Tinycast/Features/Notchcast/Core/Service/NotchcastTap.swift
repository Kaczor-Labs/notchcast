import AppKit
import CoreGraphics

enum NotchcastTapVerdict: Sendable {
    case pass
    case swallow
}

/// What an observing tap receives on the main actor, copied out of the CGEvent on the tap thread.
struct NotchcastTapEvent: Sendable {
    let type: CGEventType
    let location: CGPoint
    let flags: CGEventFlags
    let keyCode: Int64
    let button: Int64
    let isRepeat: Bool
    let isSynthetic: Bool
    let timestamp: CGEventTimestamp
    let mediaKey: NotchcastMediaKey?

    init(type: CGEventType, event: CGEvent, syntheticTag: Int64) {
        self.type = type
        location = event.location
        flags = event.flags
        keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        button = event.getIntegerValueField(.mouseEventButtonNumber)
        isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        isSynthetic = event.getIntegerValueField(.eventSourceUserData) == syntheticTag
        timestamp = event.timestamp
        mediaKey = Self.mediaKey(type: type, event: event)
    }

    /// `data1` has no CGEventField, so NSEvent is the only public reader of a media key.
    static func mediaKey(type: CGEventType, event: CGEvent) -> NotchcastMediaKey? {
        guard type.rawValue == NotchcastMediaKey.eventType, let ns = NSEvent(cgEvent: event) else { return nil }
        return NotchcastMediaKey(subtype: Int(ns.subtype.rawValue), data1: ns.data1)
    }
}

/// One subscription to the shared tap, owned by a switch: it lives only while that switch is on.
struct NotchcastTap: Sendable {
    /// Runs on the tap thread: never wait for the main actor, retain the event, or block.
    typealias Synchronous = @Sendable (CGEventType, CGEvent) -> NotchcastTapVerdict
    typealias Observer = @MainActor @Sendable (NotchcastTapEvent) -> Void

    enum Handler: Sendable {
        case synchronous(Synchronous)
        case observe(Observer)
    }

    let switchID: String
    let mask: CGEventMask
    var skipsSynthetic = true
    let handler: Handler
    /// Called after macOS disabled the tap and the hub re-enabled it, since events were lost.
    var reset: (@MainActor @Sendable () -> Void)?
}
