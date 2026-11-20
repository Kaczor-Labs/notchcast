import SwiftUI

struct URLCleanerSettingsView: View {
    @AppStorage private var extra: String
    @AppStorage private var kept: String
    @AppStorage private var sites: String
    private static let anchor = NotchcastSettingsSearch.anchor(.launcher)

    init(defaults: UserDefaults) {
        _extra = AppStorage(wrappedValue: "", URLCleanerPolicy.Key.extra, store: defaults)
        _kept = AppStorage(wrappedValue: "", URLCleanerPolicy.Key.kept, store: defaults)
        _sites = AppStorage(wrappedValue: "", URLCleanerPolicy.Key.sites, store: defaults)
    }

    var body: some View {
        row(
            LocalizedStringResource("Extra parameters to remove", table: "NotchcastURLCleaner"),
            LocalizedStringResource("Names separated by commas.", table: "NotchcastURLCleaner"),
            text: $extra, example: "ref, source")
        row(
            LocalizedStringResource("Parameters to keep", table: "NotchcastURLCleaner"),
            LocalizedStringResource("Never removed, even when listed elsewhere.", table: "NotchcastURLCleaner"),
            text: $kept, example: "utm_source, utm_*")
        row(
            LocalizedStringResource("Per-site rules", table: "NotchcastURLCleaner"),
            LocalizedStringResource(
                "One site and its parameters, as host=name,name; separate sites with semicolons.",
                table: "NotchcastURLCleaner"),
            text: $sites, example: "example.com=ref,source")
    }

    private func row(
        _ title: LocalizedStringResource, _ detail: LocalizedStringResource, text: Binding<String>, example: String
    ) -> some View {
        LabeledContent {
            TextField(String(localized: title), text: text, prompt: Text(verbatim: example))
                .labelsHidden()
                .font(.callout.monospaced())
                .autocorrectionDisabled()
        } label: {
            SettingsRowTitle(Self.anchor, title)
            Text(detail)
        }
    }
}
