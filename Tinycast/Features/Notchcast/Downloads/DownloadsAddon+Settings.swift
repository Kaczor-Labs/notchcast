import SwiftUI

extension DownloadsAddon {
    static var settings: [NotchcastSettingsRow] {
        [NotchcastSettingsRow(switchID: DownloadsModule.torrentsSwitchID) { AnyView(TorrentsSettingsView(context: $0)) }]
    }
}
