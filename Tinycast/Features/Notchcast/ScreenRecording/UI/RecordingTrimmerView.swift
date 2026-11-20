// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's editor view: the filmstrip, its dimmed ends and its two handles.

import AVKit
import SwiftUI

struct RecordingTrimmerView: View {
    let trimmer: RecordingTrimmer

    var body: some View {
        VStack(spacing: 0) {
            VideoPlayer(player: trimmer.player)
                .frame(width: Theme.Size.cameraStage.width, height: Theme.Size.cameraStage.height)
            RecordingTrimBar(trimmer: trimmer)
                .frame(height: Theme.Size.keyCap * 2)
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

/// The clip as a strip of frames: the kept part bright, a handle at each end, draggable and adjustable.
private struct RecordingTrimBar: View {
    let trimmer: RecordingTrimmer

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let trim = trimmer.trim
            let scale = trim.duration > 0 ? width / trim.duration : 0
            ZStack(alignment: .leading) {
                thumbnails
                Theme.Colors.dialogDimming
                    .frame(width: max(0, trim.start * scale))
                Theme.Colors.dialogDimming
                    .frame(width: max(0, width - trim.end * scale))
                    .offset(x: trim.end * scale)
                RoundedRectangle(cornerRadius: Theme.Radius.barControl, style: .continuous)
                    .strokeBorder(Theme.Colors.dropTarget, lineWidth: Theme.Size.hairline * 2)
                    .frame(width: max(0, trim.length * scale))
                    .offset(x: trim.start * scale)
                handle(.start, at: trim.start * scale, width: width, scale: scale)
                handle(.end, at: trim.end * scale, width: width, scale: scale)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.barControl, style: .continuous))
            .coordinateSpace(.named(Self.space))
        }
    }

    private var thumbnails: some View {
        HStack(spacing: 0) {
            if trimmer.thumbnails.isEmpty {
                Rectangle().fill(Theme.Colors.rowHover)
            } else {
                ForEach(Array(trimmer.thumbnails.enumerated()), id: \.offset) { _, image in
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
            }
        }
        .accessibilityHidden(true)
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
