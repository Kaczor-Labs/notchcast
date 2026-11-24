import SwiftUI

// About keeps upstream's GitHub link for credit and adds ours; the rest point at Tinycast's channels.
enum NotchcastAbout {
    static let hiddenLinkIDs: Set<String> = ["website", "discord", "x", "email"]

    static func links(_ upstream: [AboutLink]) -> [AboutLink] {
        upstream.filter { !hiddenLinkIDs.contains($0.id) } + [repository]
    }

    private static let repository = AboutLink(
        id: "notchcast", glyph: .brand("BrandGitHub"), title: String(localized: "Notchcast", table: "Notchcast"),
        detail: "github.com/Kaczor-Labs/notchcast",
        url: URL(string: "https://github.com/Kaczor-Labs/notchcast")!)
}

struct NotchcastAboutSection: View {
    var body: some View {
        Section {
            Text("Notchcast is a fork of Tinycast by Abue Ammar.", tableName: "Notchcast")
                .foregroundStyle(.secondary)
        }
    }
}
