import Foundation

extension ShowDesktopSystem {
    private typealias DockNotification = @convention(c) (CFString, Int32) -> Int32

    /// Private Dock SPI; ApplicationServices stays loaded with AppKit, so the handle is never closed.
    private static let dockNotification: DockNotification? = {
        guard let handle = dlopen(
            "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY),
            let symbol = dlsym(handle, "CoreDockSendNotification")
        else { return nil }
        return unsafeBitCast(symbol, to: DockNotification.self)
    }()

    static let live = ShowDesktopSystem(
        standardFunctionKeys: { UserDefaults.standard.bool(forKey: ShowDesktopPolicy.standardFunctionKeysDefaultsKey) },
        preferenceCenter: DistributedNotificationCenter.default(),
        toggleDesktop: { _ = dockNotification?("com.apple.showdesktop.awake" as CFString, 0) }
    )
}
