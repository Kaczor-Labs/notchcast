import SwiftUI

struct QuitProtectionExceptionRow: View {
    let remove: () -> Void
    private let url: URL?
    private let name: String

    init(identifier: String, remove: @escaping () -> Void) {
        self.remove = remove
        url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
        name = url.map { QuitProtectionAppName.displayName(FileManager.default.displayName(atPath: $0.path)) }
            ?? identifier
    }

    var body: some View {
        SettingsRow(title: name) {
            Group {
                if let url {
                    Image(nsImage: IconCache.icon(forFile: url.path))
                        .resizable()
                        .id(IconCache.style.generation)
                } else {
                    Color.clear
                }
            }
            .frame(width: Theme.Size.settingsRowIcon, height: Theme.Size.settingsRowIcon)
            .accessibilityHidden(true)
        } trailing: {
            Button(action: remove) {
                SymbolImage(name: "xmark.circle.fill", size: Theme.Size.menuIcon)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help(Text("Remove \(name)", tableName: "NotchcastQuitProtection"))
            .accessibilityLabel(Text("Remove \(name)", tableName: "NotchcastQuitProtection"))
        }
    }
}
