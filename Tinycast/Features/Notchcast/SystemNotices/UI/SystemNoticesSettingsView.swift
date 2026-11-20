import SwiftUI

/// One checkbox per notice kind under the System notices switch; each is on until the user turns it off.
struct SystemNoticesSettingsView: View {
    @AppStorage private var wifi: Bool
    @AppStorage private var vpn: Bool
    @AppStorage private var battery: Bool
    private static let anchor = NotchcastSettingsSearch.anchor(.notices)

    init(defaults: UserDefaults) {
        _wifi = AppStorage(wrappedValue: true, SystemNoticesPolicy.wifiKey, store: defaults)
        _vpn = AppStorage(wrappedValue: true, SystemNoticesPolicy.vpnKey, store: defaults)
        _battery = AppStorage(wrappedValue: true, SystemNoticesPolicy.batteryKey, store: defaults)
    }

    var body: some View {
        Toggle(isOn: $wifi) {
            SettingsRowTitle(Self.anchor, LocalizedStringResource("Wi-Fi", table: "NotchcastSystemNotices"))
            Text("When Wi-Fi drops and when it returns. A drop shorter than 5 seconds is skipped.",
                 tableName: "NotchcastSystemNotices")
        }
        .toggleStyle(.checkbox)
        Toggle(isOn: $vpn) {
            SettingsRowTitle(Self.anchor, LocalizedStringResource("VPN", table: "NotchcastSystemNotices"))
            Text("When a VPN tunnel goes down and when it comes back: WireGuard, Tailscale, IKEv2 and the like.",
                 tableName: "NotchcastSystemNotices")
        }
        .toggleStyle(.checkbox)
        Toggle(isOn: $battery) {
            SettingsRowTitle(Self.anchor, LocalizedStringResource("Low battery", table: "NotchcastSystemNotices"))
            Text("Once per discharge, when the charge falls to 20 percent. macOS keeps its own warning near 10 percent.",
                 tableName: "NotchcastSystemNotices")
        }
        .toggleStyle(.checkbox)
    }
}
