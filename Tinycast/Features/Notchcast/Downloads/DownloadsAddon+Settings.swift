import SwiftUI

extension DownloadsAddon {
    static var settings: [NotchcastSettingsRow] {
        [
            NotchcastSettingsRow(switchID: DownloadsModule.torrentsSwitchID) { AnyView(TorrentsSettingsView(context: $0)) },
            NotchcastSettingsRow(switchID: DownloadsModule.distillSwitchID) { AnyView(DistillSettingsView(defaults: $0.defaults)) },
        ]
    }
}
