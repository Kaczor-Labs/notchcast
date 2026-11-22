import SwiftUI

extension DownloadsAddon {
    static var settings: [NotchcastSettingsRow] {
        [
            NotchcastSettingsRow(switchID: DownloadsModule.torrentsSwitchID) { _ in AnyView(TorrentsSettingsView()) },
            NotchcastSettingsRow(switchID: DownloadsModule.distillSwitchID) { AnyView(DistillSettingsView(defaults: $0.defaults)) },
        ]
    }
}
