import SwiftUI

struct CleanerSettings: View {
    @AppStorage private var offersEmptyTrash: Bool

    init(context: NotchcastContext) {
        _offersEmptyTrash = AppStorage(
            wrappedValue: true, CleanerModule.offersEmptyTrash, store: context.defaults)
    }

    var body: some View {
        Toggle(isOn: $offersEmptyTrash) {
            Text("Offer to empty the Trash", tableName: "NotchcastCleaner")
        }
    }
}
