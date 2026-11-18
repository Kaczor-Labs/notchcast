// notchcast-sources: Tinycast/Platform/Appearance.swift Tinycast/DesignSystem/Theme.swift
// notchcast-sources: Tinycast/Features/Notchcast/NotchTheme.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandLevelDwell.swift
// notchcast-sources: Tinycast/Features/Island/Model/PillMenuRows.swift Tinycast/Features/Calendar/Model/*.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandNoticeArt.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandLevelArt.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandKeyline.swift Tinycast/Features/Island/Model/IslandLook.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandCanvas.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandExpansionArt.swift
// notchcast-sources: Tinycast/Features/Notchcast/System/Model/*.swift
import AppKit
import SwiftUI

/// #977's closed island while hot: the status glyph and its word, in both forms, Black and Frosted.
/// `NC_AUDIT_RENDERS` names the folder, else the audit harness's own, which CI uploads.
@MainActor
@main
struct SystemStatusRenderTest {
    static let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["NC_AUDIT_RENDERS"]
        ?? NSTemporaryDirectory() + "nc-island-audit-renders")
    static let notchSize = CGSize(width: 185, height: 32)
    static let margin: CGFloat = 32

    static func main() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let status = SystemPage.status([.thermal, .cpu]) else { preconditionFailure("a hot Mac has a status") }
        for frosted in [false, true] {
            for notch in [false, true] {
                let art = IslandStatusArt([status], notch: notch, frosted: frosted)
                precondition(art.layout.leading + art.layout.trailing <= 2 * NotchTheme.Size.islandGlanceWing,
                             "the hot status fits the closed island's wings")
                try render("977-closed-hot-\(notch ? "notch" : "island")-\(frosted ? "frosted" : "black")", art,
                           notch: notch, frosted: frosted)
            }
        }
        print("PASS rendered the hot closed island to \(folder.path)")
    }

    /// The closed island hanging from the screen's top edge, its ends hugging the art as the engine sizes them.
    static func render(_ name: String, _ art: IslandStatusArt, notch: Bool, frosted: Bool) throws {
        let inset = Theme.Spacing.lg + (notch ? Theme.Spacing.md : 0)
        let width = max((notch ? notchSize.width : 0) + 2 * inset + art.layout.leading + art.layout.trailing,
                        NotchTheme.Size.islandRest.width)
        let height = notch ? notchSize.height : NotchTheme.Size.islandRest.height
        let canvas = CGSize(width: width + 2 * margin, height: height + margin)
        let image = NSImage(size: canvas, flipped: false) { rect in
            (frosted ? NSColor.white : NSColor(white: 0.18, alpha: 1)).setFill()
            rect.fill()
            let pill = CGRect(x: margin, y: margin, width: width, height: height)
            // Taller than the canvas, so only the bottom corners round: the top is the screen's edge.
            let shape = NSBezierPath(roundedRect: pill.insetBy(dx: 0, dy: -height).offsetBy(dx: 0, dy: height),
                                     xRadius: height / 2, yRadius: height / 2)
            NSColor(frosted ? NotchTheme.Colors.islandGlassTint : NotchTheme.Colors.islandSurface).setFill()
            shape.fill()
            if notch {
                NSColor.black.setFill()
                CGRect(x: pill.minX + inset + art.layout.leading, y: pill.minY, width: notchSize.width,
                       height: height).fill()
            }
            art.draw(in: pill)
            return true
        }
        var proposed = CGRect(origin: .zero, size: canvas)
        guard let scaled = image.cgImage(forProposedRect: &proposed, context: nil,
                                         hints: [.ctm: AffineTransform(scale: 2)]),
              let png = NSBitmapImageRep(cgImage: scaled).representation(using: .png, properties: [:]) else {
            preconditionFailure("\(name) did not render")
        }
        try png.write(to: folder.appendingPathComponent("\(name).png"))
    }
}
