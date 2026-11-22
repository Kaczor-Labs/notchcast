// notchcast-hosted-only
import AppKit
import SwiftUI

@MainActor
enum IslandAuditRendering {
    static let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["NC_AUDIT_RENDERS"]
        ?? NSTemporaryDirectory() + "nc-island-audit-renders")
    /// `NC_AUDIT_LOOK=frosted` renders Frosted on its glass tint over a white wallpaper.
    static let frosted = ProcessInfo.processInfo.environment["NC_AUDIT_LOOK"] == "frosted"
    static let notchSize = CGSize(width: 185, height: 32)
    static let blackDesk = NSColor(white: 0.18, alpha: 1)

    static func prepare() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        // ImageRenderer draws no Liquid Glass until a hosting view has laid glass out once.
        NSHostingView(rootView: Color.clear.frosted(in: Circle())).layoutSubtreeIfNeeded()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    static let swatches = [
        ("10s-notice-swatch-blue", "#12ABEF", 0x12ABEF),
        ("10t-notice-swatch-black", "#000000", 0),
        ("10u-notice-swatch-white", "#FFFFFF", 0xFFFFFF),
        ("10v-notice-swatch-graphite", "#1C1D20", 0x1C1D20),
        ("10w-notice-swatch-rgb", "rgb(18, 171, 239)", 0x12ABEF),
    ].map { key, text, hex in
        let notice = IslandNotice(id: "pick", symbol: "eyedropper", text: text, swatch: IslandSwatch(red: Double(hex >> 16)
            / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255))
        return (key, notice)
    }

    static func write(_ name: String, _ image: CGImage?) {
        guard let image else { preconditionFailure("\(name) did not render") }
        let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        guard let data else { preconditionFailure("\(name) has no PNG") }
        do {
            try data.write(to: folder.appendingPathComponent("\(name).png"))
        } catch {
            preconditionFailure("\(name): \(error)")
        }
    }

    /// Engine art draws in AppKit into the pill's outline, so it renders the way the canvas does.
    static func renderArt(_ name: String, _ art: some PillArt) {
        let width = art.layout.leading + art.layout.trailing + 2 * Theme.Spacing.lg
        let size = CGSize(width: max(width, NotchTheme.Size.islandRest.width), height: 36)
        writeArt(name, size: CGSize(width: size.width + 32, height: size.height + 32)) { rect in
            let pill = CGRect(x: 16, y: 16, width: size.width, height: size.height)
            paintPill(rect, pill: NSBezierPath(roundedRect: pill, xRadius: size.height / 2, yRadius: size.height / 2))
            art.draw(in: pill)
        }
    }

    /// Black's pill on a grey desk; Frosted's glass tint over a white wallpaper, as the canvas fills it.
    static func paintPill(_ rect: CGRect, pill: NSBezierPath) {
        (frosted ? NSColor.white : blackDesk).setFill()
        rect.fill()
        NSColor(frosted ? NotchTheme.Colors.islandGlassTint : NotchTheme.Colors.islandSurface).setFill()
        pill.fill()
    }

    static func writeArt(_ name: String, size: CGSize, _ draw: @escaping (CGRect) -> Void) {
        let image = NSImage(size: size, flipped: false) { rect in
            draw(rect)
            return true
        }
        var proposed = CGRect(origin: .zero, size: size)
        write(name, image.cgImage(forProposedRect: &proposed, context: nil, hints: [.ctm: AffineTransform(scale: 2)]))
    }

    /// Draws the island hanging from the top edge, `body` tall below the notch, art in that lower part.
    static func island(_ name: String, width: CGFloat, body: CGFloat, notch: Bool, radius: CGFloat,
                       notchLeft: CGFloat? = nil, _ draw: @escaping (CGRect) -> Void) {
        let top = notch ? notchSize.height : 0
        let size = CGSize(width: max(width, notch ? notchSize.width : NotchTheme.Size.islandRest.width) + 64,
                          height: top + body + 32)
        writeArt(name, size: size) { rect in
            let shape = CGRect(x: 32, y: rect.maxY - top - body, width: size.width - 64, height: top + body)
            let path = NSBezierPath()
            path.move(to: CGPoint(x: shape.minX, y: rect.maxY))
            path.line(to: CGPoint(x: shape.minX, y: shape.minY + radius))
            path.appendArc(withCenter: CGPoint(x: shape.minX + radius, y: shape.minY + radius), radius: radius,
                           startAngle: 180, endAngle: 270)
            path.line(to: CGPoint(x: shape.maxX - radius, y: shape.minY))
            path.appendArc(withCenter: CGPoint(x: shape.maxX - radius, y: shape.minY + radius), radius: radius,
                           startAngle: 270, endAngle: 360)
            path.line(to: CGPoint(x: shape.maxX, y: rect.maxY))
            path.close()
            paintPill(rect, pill: notch || body > NotchTheme.Size.islandRest.height ? path
                      : NSBezierPath(roundedRect: shape, xRadius: body / 2, yRadius: body / 2))
            if notch {
                NSColor.black.setFill()
                CGRect(x: shape.minX + (notchLeft ?? (shape.width - notchSize.width) / 2),
                       y: rect.maxY - notchSize.height,
                       width: notchSize.width, height: notchSize.height).fill()
            }
            draw(notch && body == 0 ? CGRect(x: shape.minX, y: shape.minY, width: shape.width, height: top)
                 : CGRect(x: shape.minX, y: shape.minY, width: shape.width, height: body))
        }
    }

    /// The compact pill: content hugs the ends, a notch keeps the middle, as the engine sizes the slots.
    static func compactWidth(_ art: some PillArt, notch: Bool) -> CGFloat {
        let inner = notch ? Theme.Spacing.md : 0
        return (notch ? notchSize.width : 0) + 2 * (Theme.Spacing.lg + inner) + art.layout.leading
            + art.layout.trailing
    }

    static func compact(_ name: String, _ art: some PillArt, notch: Bool) {
        island(name, width: compactWidth(art, notch: notch), body: notch ? 0 : NotchTheme.Size.islandRest.height,
               notch: notch, radius: notch ? 10 : 12,
               notchLeft: Theme.Spacing.lg + Theme.Spacing.md + art.layout.leading) { art.draw(in: $0) }
    }
}
