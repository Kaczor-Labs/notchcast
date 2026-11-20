import Foundation

/// Runs whatever the switches say, so a torrent opened while Downloads is off is refused out loud.
@MainActor
final class TorrentOpenFallback: NotchcastModule {
    private let context: NotchcastContext
    /// Lives here, not in the module, which stops with the last Downloads switch and at quit.
    let defaultApp: TorrentDefaultHandler

    init(context: NotchcastContext, system: TorrentDefaultHandler.System) {
        self.context = context
        defaultApp = TorrentDefaultHandler(context: context, switchID: DownloadsModule.torrentsSwitchID, system: system)
    }

    func start() {
        context.handleOpenURL { [context] url in
            guard TorrentInput.classify(url) != nil else { return false }
            DownloadsModule.post(.notRunning, to: context.presenter)
            return true
        }
        defaultApp.start()
    }

    func stop() {
        context.handleOpenURL(nil)
        defaultApp.stop()
    }
}
