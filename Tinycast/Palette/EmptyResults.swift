import SwiftUI

struct EmptyResults: View {
    let text: String
    var detail: String?
    var systemImage = "magnifyingglass"

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage).font(.largeTitle)
                .symbolRenderingMode(.hierarchical).foregroundStyle(Theme.Colors.textTertiary)
            Text(text).foregroundStyle(Theme.Colors.textSecondary)
            if let detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
