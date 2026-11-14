import AppKit
import IslandCore
import QuartzCore

/// Frames from a screen's refresh, independent of the lifetime of any hosted view.
@MainActor
public final class DisplayLinkFrameSource: FrameSource {
    /// Holds the link's strong reference to its target, so the source can still be released.
    private final class Relay: NSObject {
        weak var source: DisplayLinkFrameSource?

        @MainActor @objc func fire(_ link: CADisplayLink) {
            source?.fire(link)
        }
    }

    struct Screen {
        let id: UInt32
        let display: NSScreen?

        init(id: UInt32, display: NSScreen? = nil) {
            self.id = id
            self.display = display
        }

        init?(_ display: NSScreen?) {
            guard let display,
                  let number = display.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            self.init(id: number.uint32Value, display: display)
        }
    }

    final class Root: NSView {
        weak var source: DisplayLinkFrameSource?
        private var visibility: NSKeyValueObservation?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // KVO's handler is @Sendable, so the main actor resumes on the run loop's next pass.
            visibility = window?.observe(\.isVisible) { [weak self] _, _ in
                guard let self else { return }
                RunLoop.main.perform(#selector(visibilityChanged), target: self, argument: nil, order: 0, modes: [.common])
            }
            source?.updateRoot(self)
        }

        @objc private func visibilityChanged() {
            source?.updateScreen()
        }

        override func viewDidHide() {
            super.viewDidHide()
            source?.updateScreen()
        }

        override func viewDidUnhide() {
            super.viewDidUnhide()
            source?.updateScreen()
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func isAccessibilityElement() -> Bool { false }
    }

    private struct WeakRoot {
        weak var view: Root?
    }

    /// Tracks this view's screen without binding the display link to the view itself.
    /// With no visible root, the source keeps its last screen while it is connected, else the main screen.
    public weak var host: NSView? {
        didSet {
            guard host !== oldValue else { return }
            hostRoot?.removeFromSuperview()
            hostRoot = host.map { track($0) }
        }
    }
    private var hostRoot: Root?
    private var roots: [WeakRoot] = []
    private var observers: [NotificationCenter.ObservationToken] = []
    private(set) var screen: Screen?
    var screenForWindow: (NSWindow) -> Screen? = { Screen($0.screen) }
    var connected: (Screen) -> Bool = { screen in NSScreen.screens.contains { $0 === screen.display } }
    private var link: CADisplayLink?
    private let relay = Relay()
    private var pending: [Int: @MainActor () -> Void] = [:]
    private var nextToken = 1

    public init(host: NSView? = nil) {
        relay.source = self
        let messages: [any MainActorNotification.Type] = [
            WindowDidChangeScreen.self, WindowDidMiniaturize.self, WindowDidDeminiaturize.self, ScreenParametersDidChange.self,
        ]
        observers = messages.map { message in
            NotificationCenter.default.addObserver(for: message) { [weak self] _ in self?.updateScreen() }
        }
        self.host = host
        hostRoot = host.map { track($0) }
    }

    func track(_ view: NSView) -> Root {
        let root = Root(frame: .zero)
        root.source = self
        view.addSubview(root)
        return root
    }

    private func updateRoot(_ root: Root) {
        roots.removeAll { $0.view == nil || $0.view === root }
        if root.window != nil {
            roots.append(WeakRoot(view: root))
        }
        updateScreen()
    }

    private func updateScreen() {
        let visible = roots.reversed().compactMap { entry -> Screen? in
            guard let root = entry.view, !root.isHiddenOrHasHiddenAncestor,
                  let window = root.window, window.isVisible, !window.isMiniaturized else { return nil }
            return screenForWindow(window)
        }.first
        // An unplugged display's link never fires again, which would stall every pending timer.
        let last = screen.flatMap { connected($0) ? $0 : nil }
        guard let next = visible ?? last ?? Screen(NSScreen.main), next.id != screen?.id else { return }
        screen = next
        link?.invalidate()
        link = nil
        if !pending.isEmpty { relink() }
    }

    public func requestFrame(_ frame: @escaping @MainActor () -> Void) -> Int {
        let token = nextToken
        nextToken += 1
        pending[token] = frame
        if link == nil {
            updateScreen()
            if link == nil { relink() }
        }
        link?.isPaused = false
        return token
    }

    private func relink() {
        let link = screen?.display?.displayLink(target: relay, selector: #selector(Relay.fire(_:)))
        link?.add(to: .main, forMode: .common)
        link?.isPaused = pending.isEmpty
        self.link = link
    }

    public func cancelFrame(_ token: Int) {
        pending[token] = nil
        if pending.isEmpty { link?.isPaused = true }
    }

    private func fire(_ link: CADisplayLink) {
        let due = pending
        pending = [:]
        link.isPaused = true
        for token in due.keys.sorted() { due[token]?() }
    }

    isolated deinit {
        link?.invalidate()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        hostRoot?.removeFromSuperview()
    }
}
