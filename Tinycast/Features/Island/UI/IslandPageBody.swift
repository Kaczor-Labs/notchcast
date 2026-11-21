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

/// The player's block: artwork, title and artist with the like toggle, the running time, transport and
/// volume; Up Next beside it when anything is queued.
struct IslandMediaView: View {
    let media: IslandMedia
    let act: (String) -> Void
    @Environment(\.metrics) private var metrics

    var body: some View {
        HStack(alignment: .top, spacing: metrics.spacing.xl) {
            player
            if !media.upNext.isEmpty {
                VStack(alignment: .leading, spacing: metrics.spacing.xxs) {
                    IslandCardHeader(title: String(localized: "Up Next", table: "Notchcast"))
                    ForEach(Array(media.upNext.enumerated()), id: \.offset) { _, row in
                        IslandPageRowView(row: row, act: act)
                    }
                }
                .frame(width: NotchTheme.Size.islandHeadlineMaxWidth, alignment: .leading)
            }
        }
        .padding(metrics.spacing.md)
    }

    private var player: some View {
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
                if let like = media.like {
                    Spacer(minLength: 0)
                    IslandPageIconButton(button: like) { act(like.id) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let time = media.time {
                TimelineView(.periodic(from: time.sampledAt, by: 1)) { context in
                    IslandMediaTimeView(time: time, now: context.date,
                                        seek: media.seekable ? { act(IslandMedia.action(IslandMedia.seekAction, $0)) }
                                                             : nil)
                }
            }
            HStack(spacing: metrics.spacing.md) {
                ForEach(media.buttons, id: \.id) { button in
                    IslandPageIconButton(button: button) { act(button.id) }
                }
            }
            if let volume = media.volume {
                HStack(spacing: metrics.spacing.md) {
                    SymbolImage(name: "speaker.fill", size: metrics.scaled(Theme.Typography.menuSymbolSize),
                                monochrome: true)
                    IslandPageBar(fraction: volume, step: 0.1, live: true) {
                        act(IslandMedia.action(IslandMedia.volumeAction, $0))
                    }
                    .accessibilityLabel(String(localized: "Volume"))
                    .accessibilityValue(volume.formatted(.percent.precision(.fractionLength(0))))
                    SymbolImage(name: "speaker.wave.3.fill", size: metrics.scaled(Theme.Typography.menuSymbolSize),
                                monochrome: true)
                }
                .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }
}

/// Elapsed time, the bar, and the time left, all in the notice's track and ink (design §10).
struct IslandMediaTimeView: View {
    let time: IslandMediaTime
    let now: Date
    /// Set, a click or drag on the bar seeks to that fraction.
    var seek: ((Double) -> Void)?
    @Environment(\.metrics) private var metrics

    var body: some View {
        let elapsed = time.elapsed(at: now)
        HStack(spacing: metrics.spacing.md) {
            Text(Self.clock(elapsed)).accessibilityHidden(true)
            IslandPageBar(fraction: time.fraction(at: now), step: time.duration > 0 ? 10 / time.duration : 0,
                          change: seek)
                .accessibilityLabel(String(localized: "Elapsed", table: "Notchcast"))
                .accessibilityValue(Self.clock(elapsed) + " / " + Self.clock(time.duration))
            Text("-" + Self.clock(max(time.duration - elapsed, 0))).accessibilityHidden(true)
        }
        .font(metrics.typography.rowTrailing.monospacedDigit())
        .foregroundStyle(Theme.Colors.textSecondary)
    }

    static func clock(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds.rounded(.down)).formatted(.time(pattern: .minuteSecond))
    }
}

/// A track and its fill from the leading edge, as the volume HUD draws it; with `change`, a slider.
struct IslandPageBar: View {
    let fraction: Double
    /// What VoiceOver's increment and decrement move by.
    var step = 0.0
    /// Sends while the drag lasts, as volume does; otherwise only on release, so a seek happens once.
    var live = false
    var change: ((Double) -> Void)?
    @Environment(\.metrics) private var metrics
    /// The drag's fraction while it lasts, so the fill follows the pointer before the player answers.
    @State private var dragged: Double?
    @State private var sent: ContinuousClock.Instant?
    @State private var trailing: Task<Void, Never>?
    /// A live drag sends at most this often (Aural's `VolumeSlider`), its last value once still.
    static let sendInterval = Duration.milliseconds(100)

    var body: some View {
        let fraction = dragged ?? self.fraction
        let bar = Capsule()
            .fill(Theme.Colors.border)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule().fill(Theme.Colors.textPrimary)
                        .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: metrics.size.volumeTrackHeight)
        if let change {
            // The track is a few points tall, so the whole row height takes the click.
            GeometryReader { proxy in
                bar.frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let value = min(max(drag.location.x / max(proxy.size.width, 1), 0), 1)
                            dragged = value
                            guard live else { return }
                            trailing?.cancel()
                            let now = ContinuousClock.now
                            let wait = sent.map { Self.sendInterval - (now - $0) } ?? .zero
                            guard wait > .zero else {
                                sent = now
                                return change(value)
                            }
                            trailing = Task {
                                try? await Task.sleep(for: wait)
                                guard !Task.isCancelled else { return }
                                sent = .now
                                change(value)
                            }
                        }
                        .onEnded { drag in
                            trailing?.cancel()
                            trailing = nil
                            change(min(max(drag.location.x / max(proxy.size.width, 1), 0), 1))
                            dragged = nil
                            sent = nil
                        })
            }
            .onDisappear { trailing?.cancel() }
            .frame(height: metrics.size.menuRowHeight / 2)
            .accessibilityElement(children: .ignore)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: change(fraction + step)
                case .decrement: change(fraction - step)
                @unknown default: break
                }
            }
        } else {
            bar.accessibilityElement(children: .ignore)
        }
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
            label.accessibilityElement(children: row.spoken == nil ? .combine : .ignore)
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
