import SwiftUI

struct ApplicationsSettingsView: View {
    @Environment(VisibilityStore.self) private var visibility
    var body: some View {
        Form {
            LauncherCategorySwitchSection(
                kind: .application, anchor: .applicationsApplications,
                title: "Enable Applications")

            SearchScopesSection()
                .notchcastHidden(!visibility.isKindEnabled(.application))

            LauncherItemsSection(
                kind: .application,
                anchor: .applicationsApplications,
                searchPrompt: "Search applications…",
                emptyMessage: LocalizedStringResource("applications-empty", defaultValue: "Nothing here yet.")
            )
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.applications)
        .releasesFocusOnOutsideClick()
    }

}
