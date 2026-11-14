import AppKit

/// An AppKit notification delivered synchronously to a main-actor observer.
/// shortcut: AppKit's own messages need macOS 27; switch to them when that is the floor.
protocol MainActorNotification: NotificationCenter.MainActorMessage where Subject == NSObject {
    init()
}

extension MainActorNotification {
    @MainActor static func makeMessage(_ notification: Notification) -> Self? { Self() }
}

struct WindowDidChangeScreen: MainActorNotification { static let name = NSWindow.didChangeScreenNotification }
struct WindowDidMiniaturize: MainActorNotification { static let name = NSWindow.didMiniaturizeNotification }
struct WindowDidDeminiaturize: MainActorNotification { static let name = NSWindow.didDeminiaturizeNotification }
struct WindowDidResize: MainActorNotification { static let name = NSWindow.didResizeNotification }
struct ScreenParametersDidChange: MainActorNotification {
    static let name = NSApplication.didChangeScreenParametersNotification
}
