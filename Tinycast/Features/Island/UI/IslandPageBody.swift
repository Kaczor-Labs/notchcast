import SwiftUI

/// A page's blocks top to bottom; each kind of `IslandPageBlock` is drawn here and nowhere else.
struct IslandPageBody: View {
    let blocks: [IslandPageBlock]
    let act: (String) -> Void
    @Environment(\.metrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.xxs) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .media(let media): IslandMediaView(media: media, act: act)
                case .row(let row): IslandPageRowView(row: row, act: act)
                case .meter(let meter): IslandPageMeterView(meter: meter)
                case .columns(let groups): IslandCardColumnsView(groups: groups)
                case .cards(let group): IslandCardRowView(group: group)
                }
            }
        }
    }
}

/// The player's block: large artwork, title and artist, the running time, then transport.
struct IslandMediaView: View {
    let media: IslandMedia
    let act: (String) -> Void
    @Environment(\.metrics) private var metrics

    var body: some View {
        VStack(spacing: metrics.spacing.md) {
            HStack(spacing: metrics.spacing.xl) {
                // Concentric with the island's fixed outline, two `md` insets in from its edge (design §3).
                IslandPageArtwork(symbol: "music.note", artwork: media.artwork,
                                  side: metrics.scaled(NotchTheme.Size.islandArtwork),
                                  radius: Theme.Radius.panel - 2 * metrics.spacing.md)
                VStack(alignment: .leading, spacing: metrics.spacing.xxs) {
                    Text(media.title).font(metrics.typography.panelTitle).foregroundStyle(Theme.Colors.textPrimary)
                    if let subtitle = media.subtitle {
                        Text(subtitle).font(metrics.typography.rowTrailing)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: NotchTheme.Size.islandHeadlineMaxWidth, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let time = media.time {
                TimelineView(.periodic(from: time.sampledAt, by: 1)) { context in
                    IslandMediaTimeView(time: time, now: context.date)
                }
            }
            HStack(spacing: metrics.spacing.md) {
                ForEach(media.buttons, id: \.id) { button in
                    IslandPageIconButton(button: button) { act(button.id) }
                }
            }
        }
        .padding(metrics.spacing.md)
    }
}

/// Elapsed time, the bar, and the time left, all in the notice's track and ink (design §10).
struct IslandMediaTimeView: View {
    let time: IslandMediaTime
    let now: Date
    @Environment(\.metrics) private var metrics

    var body: some View {
        let elapsed = time.elapsed(at: now)
        HStack(spacing: metrics.spacing.md) {
            Text(Self.clock(elapsed))
            IslandPageBar(fraction: time.fraction(at: now))
            Text("-" + Self.clock(max(time.duration - elapsed, 0)))
        }
        .font(metrics.typography.rowTrailing.monospacedDigit())
        .foregroundStyle(Theme.Colors.textSecondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Elapsed", table: "Notchcast"))
        .accessibilityValue(Self.clock(elapsed) + " / " + Self.clock(time.duration))
    }

    static func clock(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds.rounded(.down)).formatted(.time(pattern: .minuteSecond))
    }
}

/// A track and its fill from the leading edge, as the volume HUD draws it.
struct IslandPageBar: View {
    let fraction: Double
    @Environment(\.metrics) private var metrics

    var body: some View {
        Capsule()
            .fill(Theme.Colors.border)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule().fill(Theme.Colors.textPrimary)
                        .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: metrics.size.volumeTrackHeight)
            .accessibilityHidden(true)
    }
}

/// A list row; with an id it is a button with the row hover, like a Home line.
struct IslandPageRowView: View {
    let row: IslandPageRow
    let act: (String) -> Void
    @Environment(\.metrics) private var metrics
    @State private var hovered = false

    var body: some View {
        let label = HStack(spacing: metrics.spacing.md) {
            IslandPageLabel(symbol: row.symbol, artwork: nil, title: row.title, detail: row.detail)
            Spacer(minLength: metrics.spacing.md)
            if let trailing = row.trailing {
                Text(trailing).font(metrics.typography.rowTrailing).foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.xs)
        .contentShape(Rectangle())
        if let id = row.id {
            Button { act(id) } label: { label }
                .buttonStyle(.plain)
                .background(RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                    .fill(hovered ? Theme.Colors.rowHover : Color.clear))
                .onHover { hovered = $0 }
                .accessibilityLabel(Text(verbatim: row.spoken ?? ""), isEnabled: row.spoken != nil)
        } else {
            label.accessibilityElement(children: .combine)
                .accessibilityLabel(Text(verbatim: row.spoken ?? ""), isEnabled: row.spoken != nil)
        }
    }
}

/// A labelled meter: label and value over the bar.
struct IslandPageMeterView: View {
    let meter: IslandPageMeter
    @Environment(\.metrics) private var metrics

    var body: some View {
        VStack(spacing: metrics.spacing.xs) {
            HStack {
                Text(meter.label).foregroundStyle(Theme.Colors.textPrimary)
                Spacer(minLength: metrics.spacing.md)
                Text(meter.value).foregroundStyle(Theme.Colors.textSecondary)
            }
            .font(metrics.typography.rowTrailing)
            IslandPageBar(fraction: meter.fraction)
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(meter.label)
        .accessibilityValue(meter.value)
    }
}
