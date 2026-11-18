import SwiftUI

// Apart from the descriptor, so the harnesses that compile it need no SwiftUI view.
extension DownloadsAddon {
    static let settings = [
        NotchcastSettingsRow(switchID: DownloadsModule.distillSwitchID) {
            AnyView(DistillSettingsView(defaults: $0.defaults))
        },
    ]
}
