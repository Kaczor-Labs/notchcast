import SwiftUI

/// The threshold under the Low disk warning switch; a change checks the disk at once.
struct LowDiskSettingsView: View {
    let context: NotchcastContext
    @AppStorage private var threshold: Int
    private static let anchor = NotchcastSettingsSearch.anchor(.power)

    init(context: NotchcastContext) {
        self.context = context
        _threshold = AppStorage(
            wrappedValue: LowDiskPolicy.defaultThresholdGB, LowDiskPolicy.thresholdKey, store: context.defaults)
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: Theme.Spacing.sm) {
                Text("\(LowDiskPolicy.thresholdGB(stored: threshold)) GB", tableName: "NotchcastLowDisk")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Stepper(value: $threshold, in: LowDiskPolicy.thresholdRange) {
                    Text("Warn below", tableName: "NotchcastLowDisk")
                }
                .labelsHidden()
            }
        } label: {
            SettingsRowTitle(Self.anchor, LocalizedStringResource("Warn below", table: "NotchcastLowDisk"))
            Text("The island warns once when free space drops below this.", tableName: "NotchcastLowDisk")
        }
        .onChange(of: threshold) { context.module(LowDiskModule.self)?.check() }
    }
}
