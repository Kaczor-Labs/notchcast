import SwiftUI

struct ArchivesSettingsView: View {
    @Environment(MainAppLink.self) private var mainApp
    @AppStorage private var defaultApp: Bool
    @AppStorage private var inPlace: Bool
    private static let anchor = NotchcastSettingsSearch.anchor(.filesDownloads)

    init(context: NotchcastContext) {
        _defaultApp = AppStorage(wrappedValue: false, ArchivesModule.defaultAppKey, store: context.defaults)
        _inPlace = AppStorage(wrappedValue: false, ArchivesModule.inPlaceKey, store: context.defaults)
    }

    var body: some View {
        notchcastSettingsToggle(
            SettingsRowTitle(
                Self.anchor, LocalizedStringResource("Make Notchcast the default app for archives", table: "NotchcastArchives")
            ),
            isOn: $defaultApp
        ) {
            Text("Off gives the archive types back to Archive Utility.", tableName: "NotchcastArchives")
        }
        .onChange(of: defaultApp) { _, on in mainApp.sendNotchcast(on, to: ArchivesAddon.self) }
        notchcastSettingsToggle(
            SettingsRowTitle(Self.anchor, LocalizedStringResource("Extract in place", table: "NotchcastArchives")),
            isOn: $inPlace
        ) {
            Text("Remove the archive as its files come out, so it needs space for the files only.",
                 tableName: "NotchcastArchives")
        }
    }
}
