import SwiftUI

/// The island's Music page, direction A (D6): the player on the left, Up Next on the right.
struct SpotifyPlayerView: View {
    static let cover = Theme.Size.rowIcon * 2 + Theme.Spacing.xs
    static let controls = Theme.Size.rowIcon + Theme.Spacing.xs
    static let height = cover + Theme.Spacing.xl + timeRow + Theme.Spacing.md + controls + Theme.Spacing.md
        + Theme.Size.rowIcon - Theme.Spacing.xs
    static let timeRow = Theme.Spacing.lg + Theme.Spacing.sm
    static let playerWidth = Theme.Size.panelWidth / 2 + Theme.Spacing.xxxl
    static let volumeStep = 5
    /// The launcher's width once the island's inset wraps it.
    static let pageSize = CGSize(width: Theme.Size.panelWidth - NotchTheme.Spacing.islandInset * 2, height: height)
    /// Wide enough for "−00:00", so the bar between the two times never moves.
    static let timeSlot = Theme.Size.headerIconSlot * 2

    let module: SpotifyModule
    /// PR C's library opens here; nil until it lands, so the page shows no dead button.
    var onLibrary: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xxl) {
            player.frame(width: Self.playerWidth)
            SpotifyUpNextView(entries: module.playback.track == nil ? [] : module.playback.upNext)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var track: SpotifyTrack? { module.playback.track }

    private var player: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.bottom, Theme.Spacing.xl)
            SpotifyProgressRow(module: module).frame(height: Self.timeRow).padding(.bottom, Theme.Spacing.md)
            transport.frame(height: Self.controls).padding(.bottom, Theme.Spacing.md)
            HStack(spacing: Theme.Spacing.lg) {
                SpotifyVolumeRow(module: module)
                Spacer(minLength: 0)
                if let onLibrary {
                    Button(action: onLibrary) {
                        Label(String(localized: "Library", table: "NotchcastSpotify"), systemImage: "music.note.list")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.Colors.textPrimary)
                }
            }
            .frame(height: Theme.Size.rowIcon - Theme.Spacing.xs)
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.xl) {
            SpotifyCoverView(url: track?.artworkURL ?? track?.thumbnailURL, side: Self.cover)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(verbatim: track?.title ?? String(localized: "Nothing Playing", table: "NotchcastSpotify"))
                    .font(Theme.Typography.panelTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(2)
                Text(verbatim: track?.artistLine
                     ?? String(localized: "Start a song in Spotify and pick this Mac.", table: "NotchcastSpotify"))
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if track != nil, let liked = module.liked {
                Button { module.toggleLike() } label: {
                    Image(systemName: liked ? "heart.fill" : "heart")
                        .font(Theme.Typography.rowTitle)
                        .frame(width: Self.controls, height: Self.controls)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityLabel(liked ? String(localized: "Remove from Liked Songs", table: "NotchcastSpotify")
                                          : String(localized: "Save to Liked Songs", table: "NotchcastSpotify"))
            }
        }
        .frame(height: Self.cover)
    }

    private var transport: some View {
        HStack(spacing: Theme.Spacing.xxl) {
            control("backward.fill", String(localized: "Previous", table: "NotchcastSpotify")) { module.previous() }
            control(module.playback.isPlaying ? "pause.fill" : "play.fill",
                    module.playback.isPlaying ? String(localized: "Pause", table: "NotchcastSpotify")
                                              : String(localized: "Play", table: "NotchcastSpotify")) {
                module.togglePlay()
            }
            control("forward.fill", String(localized: "Next", table: "NotchcastSpotify")) { module.next() }
        }
        .frame(maxWidth: .infinity)
        .disabled(track == nil)
        .opacity(track == nil ? NotchTheme.Opacity.disabled : 1)
    }

    private func control(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Theme.Typography.headerIcon)
                .frame(width: Self.controls, height: Self.controls)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.Colors.textPrimary)
        .accessibilityLabel(label)
    }
}

/// Elapsed, a bar you can drag to seek (N5), and the time left with a minus sign.
private struct SpotifyProgressRow: View {
    let module: SpotifyModule
    @State private var dragging: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let duration = module.playback.track?.durationMs ?? 0
            let position = module.playback.position.current(at: context.date, durationMs: duration)
            let fraction = dragging ?? (duration > 0 ? Double(position) / Double(duration) : 0)
            let shown = Int(fraction * Double(duration))
            HStack(spacing: Theme.Spacing.md) {
                time(shown, leading: true)
                SpotifyBar(value: fraction, label: String(localized: "Position", table: "NotchcastSpotify"),
                           readout: Self.clock(shown)) { dragging = $0 } commit: { value in
                    dragging = nil
                    module.seek(toMs: Int(value * Double(duration)))
                }
                .disabled(duration == 0)
                time(duration - shown, leading: false)
            }
        }
    }

    private func time(_ ms: Int, leading: Bool) -> some View {
        Text(verbatim: (leading ? "" : "−") + Self.clock(ms))
            .font(Theme.Typography.rowTrailing.monospacedDigit())
            .foregroundStyle(Theme.Colors.textSecondary)
            .frame(width: SpotifyPlayerView.timeSlot, alignment: leading ? .leading : .trailing)
    }

    static func clock(_ ms: Int) -> String {
        let seconds = max(ms, 0) / 1000
        return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }
}

/// Spotify's own volume, not the Mac's (D19); ↑ and ↓ move it while the page holds the keyboard.
private struct SpotifyVolumeRow: View {
    let module: SpotifyModule

    var body: some View {
        let volume = Double(module.playback.volume) / 100
        HStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "speaker.wave.2.fill", variableValue: volume)
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: Theme.Spacing.xxl, alignment: .leading)
                .accessibilityHidden(true)
            SpotifyBar(value: volume, label: String(localized: "Spotify Volume", table: "NotchcastSpotify"),
                       readout: "\(module.playback.volume)%") { module.setVolume(Int($0 * 100)) } commit: { _ in }
                .frame(width: NotchTheme.Size.islandLevelTrack)
        }
    }
}

/// A thin track the pointer drags; VoiceOver adjusts it in tenths.
private struct SpotifyBar: View {
    let value: Double
    let label: String
    let readout: String
    let change: (Double) -> Void
    let commit: (Double) -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Colors.separator)
                Capsule().fill(Theme.Colors.textPrimary)
                    .frame(width: width * min(max(value, 0), 1))
                    .opacity(isEnabled ? 1 : 0)
            }
            .frame(height: Theme.Spacing.sm)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { change(min(max($0.location.x / width, 0), 1)) }
                .onEnded { commit(min(max($0.location.x / width, 0), 1)) })
        }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(readout)
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 0.1 : -0.1
            let next = min(max(value + step, 0), 1)
            change(next)
            commit(next)
        }
    }
}
