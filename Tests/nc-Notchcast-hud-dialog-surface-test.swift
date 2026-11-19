// notchcast-hosted-only
// notchcast-sources: Tinycast/Platform/Appearance.swift Tinycast/DesignSystem/Theme.swift
// notchcast-sources: Tinycast/DesignSystem/InterfaceMetrics.swift Tinycast/Features/Notchcast/NotchTheme.swift
// notchcast-sources: Tinycast/DesignSystem/KeyCapChip.swift Tinycast/DesignSystem/ModalActionButtonStyle.swift
// notchcast-sources: Tinycast/DesignSystem/SymbolImage.swift Tinycast/DesignSystem/Tooltip.swift
// notchcast-sources: Tinycast/Windows/HUD/MessageHUDView.swift Tinycast/Windows/Dialog/DialogView.swift
// notchcast-sources: Tinycast/Windows/Dialog/DialogRequest.swift Tinycast/Platform/Images/IconCache.swift
// notchcast-sources: Tinycast/Features/Notchcast/IslandButtonFill.swift
import AppKit
import SwiftUI

/// Design system §1/§2/§10: a report HUD and a dialog are the island black alone, so every pixel
/// between their edge and their content is black or clear: no glow, scrim, rim or icon tile.
/// `NC_SURFACE_RENDERS` names a folder to keep the PNGs in.
@MainActor
@main
struct NotchcastHUDDialogSurfaceTest {
    static let scale: CGFloat = 2
    static var failures = 0

    static func main() {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let hudInset = CGSize(width: Theme.Spacing.xl, height: Theme.Spacing.lg)
        for (name, tone) in [("neutral", DialogTone.neutral), ("success", .success), ("danger", .danger)] {
            let pixels = render("hud-\(name)") {
                MessageHUDView(message: "Copied to Clipboard", accessory: .tone(tone))
            }
            checkEdges("hud-\(name)", pixels, inset: hudInset)
        }
        let progress = render("hud-progress") {
            MessageHUDView(message: "Downloading…", accessory: .progress, onCancel: {})
        }
        checkEdges("hud-progress", progress, inset: hudInset)

        let dialogInset = Theme.Spacing.dialogInset
        for (name, tone, symbol) in [("danger", DialogTone.danger, "arrow.down.circle"),
                                     ("neutral", .neutral, "safari")] {
            let pixels = render("dialog-\(name)") {
                DialogView(
                    request: DialogRequest(
                        title: "Update Failed", message: "The download did not finish.",
                        symbol: symbol, tone: tone,
                        actions: [DialogAction(title: "Cancel", role: .cancel), DialogAction(title: "Try Again")],
                        defaultIndex: 1, cancelIndex: 0),
                    width: Theme.Size.dialogCompactWidth, onChoose: { _ in })
            }
            checkEdges("dialog-\(name)", pixels, inset: CGSize(width: dialogInset, height: dialogInset))
            // Where the old 52-point tile reached past the 32-point glyph: right of it, on its row.
            let top = dialogInset + Theme.Spacing.xs
            let tile = CGRect(x: top + Theme.Size.dialogIcon + 10, y: top,
                              width: Theme.Size.dialogSymbolContainer - Theme.Size.dialogIcon - 10,
                              height: Theme.Size.dialogIcon)
            check("dialog-\(name) icon has no tile", pixels.inked(in: tile).isEmpty)
            check("dialog-\(name) icon is drawn", !pixels.inked(in: CGRect(x: top, y: top,
                width: Theme.Size.dialogIcon, height: Theme.Size.dialogIcon)).isEmpty)
        }
        guard failures == 0 else { fatalError("\(failures) surface checks failed") }
        print("PASS HUD and dialog draw the island surface alone")
    }

    static func check(_ label: String, _ ok: Bool) {
        if !ok { failures += 1; print("FAIL \(label)") }
    }

    /// The band between the edge and the content holds only black; the shape covers it opaquely.
    static func checkEdges(_ name: String, _ pixels: Pixels, inset: CGSize) {
        let size = pixels.size
        let margin: CGFloat = 1
        let bands = [
            CGRect(x: 0, y: 0, width: size.width, height: inset.height - margin),
            CGRect(x: 0, y: size.height - inset.height + margin, width: size.width, height: inset.height - margin),
            CGRect(x: 0, y: 0, width: inset.width - margin, height: size.height),
            CGRect(x: size.width - inset.width + margin, y: 0, width: inset.width - margin, height: size.height),
        ]
        let inked = bands.flatMap { pixels.inked(in: $0) }
        check("\(name) edge band is black, \(inked.count) inked pixels, first \(inked.first.map { "\($0)" } ?? "-")",
              inked.isEmpty)
        check("\(name) surface is opaque at its top centre", pixels.alpha(x: size.width / 2, y: 1) == 255)
        check("\(name) corner is outside the shape", pixels.alpha(x: 0, y: 0) == 0)
    }

    static func render(_ name: String, @ViewBuilder _ content: () -> some View) -> Pixels {
        let renderer = ImageRenderer(content: content().environment(\.colorScheme, .dark))
        renderer.scale = scale
        guard let image = renderer.cgImage else { fatalError("\(name) did not render") }
        if let folder = ProcessInfo.processInfo.environment["NC_SURFACE_RENDERS"],
           let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
            do {
                try png.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name).png"))
            } catch {
                fatalError("\(name): \(error)")
            }
        }
        return Pixels(image, scale: scale)
    }
}

/// Premultiplied RGBA, so a transparent or black pixel has all three channels at zero.
struct Pixels {
    let width: Int
    let height: Int
    let scale: CGFloat
    var bytes: [UInt8]

    init(_ image: CGImage, scale: CGFloat) {
        width = image.width
        height = image.height
        self.scale = scale
        bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                .map { $0.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height)); return true }
        }
        guard drawn == true else { fatalError("no bitmap context") }
    }

    var size: CGSize { CGSize(width: CGFloat(width) / scale, height: CGFloat(height) / scale) }

    /// Top-left origin, in points.
    func offset(x: CGFloat, y: CGFloat) -> Int {
        let column = min(width - 1, max(0, Int(x * scale)))
        let row = min(height - 1, max(0, Int(y * scale)))
        return (row * width + column) * 4
    }

    func alpha(x: CGFloat, y: CGFloat) -> UInt8 { bytes[offset(x: x, y: y) + 3] }

    /// Pixels brighter than the island black (one step of slack for rounding), in points.
    func inked(in rect: CGRect) -> [CGPoint] {
        var hits: [CGPoint] = []
        let rows = max(0, Int(rect.minY * scale))..<min(height, Int(rect.maxY * scale))
        let columns = max(0, Int(rect.minX * scale))..<min(width, Int(rect.maxX * scale))
        for row in rows {
            for column in columns {
                let index = (row * width + column) * 4
                if max(bytes[index], bytes[index + 1], bytes[index + 2]) > 2 {
                    hits.append(CGPoint(x: CGFloat(column) / scale, y: CGFloat(row) / scale))
                }
            }
        }
        return hits
    }
}

/// `DialogView`'s accessories are not under test; empty stand-ins keep it whole.
final class VolumeState {}
final class SnippetArgumentsState {}
final class ClipboardEditState {}

struct VolumeSlider: View {
    let state: VolumeState
    var body: some View { EmptyView() }
}

struct SnippetArgumentFields: View {
    let state: SnippetArgumentsState
    var body: some View { EmptyView() }
}

struct ClipboardEditField: View {
    let state: ClipboardEditState
    var body: some View { EmptyView() }
}
