import AVKit
import SwiftUI

struct RecordingTrimmerView: View {
    let trimmer: RecordingTrimmer

    var body: some View {
        VStack(spacing: 0) {
            VideoPlayer(player: trimmer.player)
                .frame(width: Theme.Size.cameraStage.width, height: Theme.Size.cameraStage.height)
            RecordingTrimBar(trimmer: trimmer)
                .frame(height: Theme.Size.barButtonHeight)
                .padding([.horizontal, .top], Theme.Spacing.xl)
            footer
        }
        .frame(width: Theme.Size.cameraStage.width)
        .background(Theme.Colors.panelScrim)
        .background(GlassEffectView())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.dialog, style: .continuous))
    }

    private var footer: some View {
        HStack(spacing: Theme.Spacing.md) {
            Text(verbatim: "\(Self.clock(trimmer.trim.start)) – \(Self.clock(trimmer.trim.end))")
                .font(Theme.Typography.rowTrailing)
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer(minLength: Theme.Spacing.md)
            Button(String(localized: "Discard", table: "NotchcastScreenRecording")) { trimmer.respond(.discard) }
                .buttonStyle(.modalAction(.destructive, fillsWidth: false))
            Button(String(localized: "Copy", table: "NotchcastScreenRecording")) {
                trimmer.respond(.copy(trimmer.trim))
            }
            .buttonStyle(.modalAction(.standard, fillsWidth: false))
            Button(String(localized: "Save", table: "NotchcastScreenRecording")) {
                trimmer.respond(.save(trimmer.trim))
            }
            .buttonStyle(.modalAction(.primary, fillsWidth: false))
            .tooltip(keyCaps: ["↵"])
        }
        .padding(Theme.Spacing.xl)
    }

    static func clock(_ seconds: TimeInterval) -> String {
        Duration.milliseconds(Int64((seconds * 1000).rounded())).formatted(
            .time(pattern: .minuteSecond(padMinuteToLength: 1, fractionalSecondsLength: 1)))
    }
}

/// The clip as a bar: the kept part filled, a handle at each end, each draggable and adjustable.
private struct RecordingTrimBar: View {
    let trimmer: RecordingTrimmer

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let trim = trimmer.trim
            let scale = trim.duration > 0 ? width / trim.duration : 0
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: Theme.Radius.barControl, style: .continuous)
                    .fill(Theme.Colors.rowHover)
                Rectangle()
                    .fill(Theme.Colors.selection)
                    .frame(width: max(0, trim.length * scale))
                    .offset(x: trim.start * scale)
                handle(.start, at: trim.start * scale, width: width, scale: scale)
                handle(.end, at: trim.end * scale, width: width, scale: scale)
            }
            .coordinateSpace(.named(Self.space))
        }
    }

    private enum Edge { case start, end }

    private func handle(_ edge: Edge, at x: CGFloat, width: CGFloat, scale: CGFloat) -> some View {
        let time = edge == .start ? trimmer.trim.start : trimmer.trim.end
        return Capsule()
            .fill(Theme.Colors.textPrimary)
            .frame(width: Theme.Spacing.sm)
            .frame(width: Theme.Size.keyCap)
            .contentShape(Rectangle())
            .offset(x: x - Theme.Size.keyCap / 2)
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space)).onChanged { value in
                guard scale > 0 else { return }
                move(edge, to: min(max(0, value.location.x), width) / scale)
            })
            .pointerStyle(.frameResize(position: edge == .start ? .leading : .trailing))
            .accessibilityElement()
            .accessibilityLabel(edge == .start
                ? Text("Trim start", tableName: "NotchcastScreenRecording")
                : Text("Trim end", tableName: "NotchcastScreenRecording"))
            .accessibilityValue(Text(verbatim: RecordingTrimmerView.clock(time)))
            .accessibilityAdjustableAction { direction in
                move(edge, to: time + (direction == .increment ? 1 : -1))
            }
    }

    private func move(_ edge: Edge, to time: TimeInterval) {
        if edge == .start { trimmer.setStart(time) } else { trimmer.setEnd(time) }
    }

    private static let space = "recording-trim-bar"
}
