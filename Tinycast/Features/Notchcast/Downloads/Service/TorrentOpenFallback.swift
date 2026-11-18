import Foundation

/// Runs whatever the switches say, so a torrent opened while Downloads is off is refused out loud.
@MainActor
final class TorrentOpenFallback: NotchcastModule {
    private let context: NotchcastContext

    init(context: NotchcastContext) {
        self.context = context
    }

    func start() {
        context.handleOpenURL { [context] url in
            guard TorrentInput.classify(url) != nil else { return false }
            DownloadsModule.post(.notRunning, to: context.presenter)
            return true
        }
    }

    func stop() {
        context.handleOpenURL(nil)
    }
}
