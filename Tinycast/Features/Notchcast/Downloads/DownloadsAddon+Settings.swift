import SwiftUI

extension DownloadsAddon {
    static var settings: [NotchcastSettingsRow] {
        [
            NotchcastSettingsRow(switchID: DownloadsModule.torrentsSwitchID, searchTerms: [
                "aria2c",
                "default torrent app",
            ]) {
                AnyView(TorrentsSettingsView(context: $0))
            },
            NotchcastSettingsRow(switchID: DownloadsModule.distillSwitchID, searchTerms: [
                "markdown folder",
                "convert dropped files",
            ]) {
                AnyView(DistillSettingsView(defaults: $0.defaults))
            },
        ]
    }
}
