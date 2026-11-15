import CoreGraphics

/// The pure rules of the shared tap: which bit an event type sets, and when macOS turned it off.
enum NotchcastTapPolicy {
    static func mask(for type: CGEventType) -> CGEventMask {
        mask(rawType: type.rawValue)
    }

    static func mask(rawType: UInt32) -> CGEventMask {
        guard rawType < CGEventMask.bitWidth else { return 0 }
        return 1 << CGEventMask(rawType)
    }

    static func options(hasSynchronousConsumers: Bool) -> CGEventTapOptions {
        hasSynchronousConsumers ? .defaultTap : .listenOnly
    }

    static func isDisabledNotice(_ type: CGEventType) -> Bool {
        type == .tapDisabledByTimeout || type == .tapDisabledByUserInput
    }
}
