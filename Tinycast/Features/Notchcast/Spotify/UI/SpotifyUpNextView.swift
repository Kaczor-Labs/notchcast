import SwiftUI

/// The songs after this one, as Spotify reports them (at most ten for a playlist or album).
struct SpotifyUpNextView: View {
    let entries: [SpotifyQueueEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: String(localized: "Up Next", table: "NotchcastSpotify"), isFirst: true)
            if entries.isEmpty {
                Text("Nothing queued", tableName: "NotchcastSpotify")
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.top, Theme.Spacing.xs)
            } else {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        ForEach(entries) { entry in row(entry.track) }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ track: SpotifyTrack) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            SpotifyCoverView(url: track.thumbnailURL ?? track.artworkURL, side: Theme.Size.rowIcon)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: track.title)
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(verbatim: track.artistLine)
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .lineLimit(1)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .accessibilityElement(children: .combine)
    }
}

/// A square cover with the shared 1 pt inside line (D21), or a tile with a note until it loads.
struct SpotifyCoverView: View {
    let url: URL?
    let side: CGFloat
    @Environment(SpotifyCovers.self) private var covers
    @State private var image: NSImage?

    var body: some View {
        let radius = side > Theme.Size.rowIcon ? Theme.Radius.thumbnail : Theme.Spacing.xs
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
            } else {
                shape.fill(NotchTheme.Colors.keyCapFill)
                Image(systemName: "music.note")
                    .font(side > Theme.Size.rowIcon ? Theme.Typography.headerIcon : Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(shape)
        .overlay(shape.strokeBorder(NotchTheme.Colors.islandEdge, lineWidth: 1))
        .accessibilityHidden(true)
        .task(id: url) { image = await covers.image(url) }
    }
}

/// Covers for the page, fetched through the add-on's own ephemeral transport and kept for the session.
@MainActor
@Observable
final class SpotifyCovers {
    @ObservationIgnored private let send: @Sendable (URLRequest) async throws -> SpotifyWebTransport.Response
    @ObservationIgnored private var cache: [URL: NSImage] = [:]

    init(send: @escaping @Sendable (URLRequest) async throws -> SpotifyWebTransport.Response) { self.send = send }

    func image(_ url: URL?) async -> NSImage? {
        guard let url else { return nil }
        if let cached = cache[url] { return cached }
        guard let response = try? await send(URLRequest(url: url)), response.status == 200,
              let image = NSImage(data: response.body) else { return nil }
        if cache.count > 64 { cache.removeAll() }
        cache[url] = image
        return image
    }
}
