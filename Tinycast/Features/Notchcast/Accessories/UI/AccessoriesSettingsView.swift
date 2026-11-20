import CoreBluetooth
import SwiftUI

/// One checkbox per notice kind under the Accessories switch, and the opt-in that hides macOS's own banner.
struct AccessoriesSettingsView: View {
    @AppStorage private var connect: Bool
    @AppStorage private var low: Bool
    @AppStorage private var hideBanner: Bool
    @State private var trusted = Permissions.isAccessibilityTrusted()
    @State private var bluetooth = CBManager.authorization
    private static let anchor = NotchcastSettingsSearch.anchor(.notices)

    init(defaults: UserDefaults) {
        _connect = AppStorage(wrappedValue: true, AccessoryPolicy.connectKey, store: defaults)
        _low = AppStorage(wrappedValue: true, AccessoryPolicy.lowKey, store: defaults)
        _hideBanner = AppStorage(wrappedValue: false, AccessoryPolicy.hideBannerKey, store: defaults)
    }

    var body: some View {
        if [.denied, .restricted].contains(bluetooth) {
            LabeledContent {
                Button(String(localized: "Grant Access…", table: "NotchcastAccessories")) {
                    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")
                    else { return }
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label(String(localized: "Needs Bluetooth access", table: "NotchcastAccessories"),
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.Colors.warning)
            }
        }
        Toggle(isOn: $connect) {
            SettingsRowTitle(Self.anchor, LocalizedStringResource("Connected", table: "NotchcastAccessories"))
            Text("When headphones, a keyboard, a mouse or another Bluetooth accessory connects. Never computers or phones.",
                 tableName: "NotchcastAccessories")
        }
        .toggleStyle(.checkbox)
        Toggle(isOn: $low) {
            SettingsRowTitle(Self.anchor, LocalizedStringResource("Low battery", table: "NotchcastAccessories"))
            Text("Once per discharge, when an accessory falls to 20 percent. Charging it to 25 percent arms it again.",
                 tableName: "NotchcastAccessories")
        }
        .toggleStyle(.checkbox)
        Toggle(isOn: $hideBanner) {
            SettingsRowTitle(Self.anchor, LocalizedStringResource("Hide the system banner", table: "NotchcastAccessories"))
            Text("Hides macOS's own banner for an accessory the island just announced. It still reaches Notification Center.",
                 tableName: "NotchcastAccessories")
        }
        .toggleStyle(.checkbox)
        .onChange(of: hideBanner) { trusted = Permissions.isAccessibilityTrusted() }
        // macOS announces no Accessibility grant; returning from System Settings keys the window.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            trusted = Permissions.isAccessibilityTrusted()
            bluetooth = CBManager.authorization
        }
        if hideBanner, !trusted {
            LabeledContent {
                Button(String(localized: "Grant Access…", table: "NotchcastAccessories")) {
                    Permissions.openAccessibilitySettings()
                }
            } label: {
                Label(String(localized: "Needs Accessibility access", table: "NotchcastAccessories"),
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.Colors.warning)
            }
        }
    }
}
