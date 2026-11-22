import AppKit
import SwiftUI

extension NotchcastIslandAuditRenderTest {
    private static let hostedPadding: CGFloat = 16
    static let blackDesk = NSColor(white: 0.18, alpha: 1)

    /// A field or scroll view is AppKit-backed and blank to `ImageRenderer`, so a window caches it.
    @discardableResult
    static func renderHosted(
        _ name: String, size: CGSize, desk: Bool = false, frosted: Bool = Self.frosted,
        @ViewBuilder _ content: () -> some View
    ) -> NSBitmapImageRep {
        let scale: CGFloat = 2
        let view = content()
            .padding(hostedPadding)
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(ground(desk: desk, frosted: frosted))
            .environment(\.islandFrosted, frosted)
            .environment(\.paletteOnIsland, true)
            .environment(\.colorScheme, .dark)
            .environment(\.displayScale, scale)
            .environment(PaletteState())
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { preconditionFailure("\(name) has no bitmap") }
        bitmap.size = size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        write(name, bitmap.cgImage)
        return bitmap
    }

    @ViewBuilder static func ground(desk: Bool, frosted: Bool = Self.frosted) -> some View {
        if desk {
            frosted ? Color.white : Color(nsColor: blackDesk)
        } else if frosted {
            NotchTheme.Colors.islandGlassTint.background(Color.white)
        } else {
            NotchTheme.Colors.islandSurface
        }
    }

    private static let menuWidth = Theme.Size.actionMenuWidth
    private static let menuInset = Theme.Spacing.md
    private static let searchSample = Theme.Size.menuRowHeight + Theme.Spacing.xxs
    private static let launcherSize = CGSize(width: Theme.Size.panelWidth, height: Theme.Size.panelHeight)

    static func actionsMenu(notch: Bool, frosted: Bool) -> some View {
        ZStack(alignment: .bottomTrailing) {
            auditLauncherBottom(notch: notch)
                .padding(.top, notch ? 16 : 0)
                .background(ground(desk: false, frosted: frosted))
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: notch ? 0 : Theme.Radius.panel, bottomLeadingRadius: Theme.Radius.panel,
                    bottomTrailingRadius: Theme.Radius.panel, topTrailingRadius: notch ? 0 : Theme.Radius.panel))
            PopoverMenu(
                items: [
                    PopoverMenuItem(title: "Open Application", systemImage: "arrow.up.right", shortcut: "↵") {},
                    PopoverMenuItem(title: "Show in Finder", systemImage: "folder", shortcut: "⌘↵") {},
                    PopoverMenuItem(title: "Copy Path", systemImage: "document.on.document", startsSection: true) {},
                ],
                selection: .constant(0), onActivate: { _ in }, attachment: .bottomTrailing,
                search: .init(placeholder: "Search for actions…", placement: .bottom))
                .padding([.trailing, .bottom], menuInset)
        }
        .frame(width: launcherSize.width, height: launcherSize.height)
    }

    static func menuPixels(_ bitmap: NSBitmapImageRep, leading: CGFloat, row: CGFloat) -> [Int] {
        let scale = CGFloat(bitmap.pixelsWide) / bitmap.size.width
        let x = Int(leading * scale)
        let y = Int(row * scale)
        return (0...Int(4 * scale)).map { offset in
            let color = bitmap.colorAt(x: x + offset, y: y)!.usingColorSpace(.sRGB)!
            return Int((max(color.redComponent, color.greenComponent, color.blueComponent) * 255).rounded())
        }
    }

    static func checkMenu(_ passed: Bool, _ name: String, _ detail: String) {
        guard passed else {
            print("FAIL \(name): \(detail)")
            exit(1)
        }
    }

    static func pillMenu(notch: Bool, frosted: Bool) -> some View {
        VStack(alignment: .leading, spacing: menuInset) {
            if notch {
                UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10)
                    .fill(.black)
                    .frame(width: 185, height: 32)
            } else {
                Capsule()
                    .fill(frosted ? NotchTheme.Colors.islandGlassTint : NotchTheme.Colors.islandSurface)
                    .frame(width: NotchTheme.Size.islandRest.width, height: NotchTheme.Size.islandRest.height)
            }
            PopoverMenu(
                header: "Notchcast",
                items: [
                    PopoverMenuItem(title: "Open Settings", systemImage: "gearshape", shortcut: "⌘,") {},
                    PopoverMenuItem(title: "Check for Updates", systemImage: "arrow.down.circle", startsSection: true) {},
                    PopoverMenuItem(title: "Quit Notchcast", systemImage: "power", isDestructive: true) {},
                ],
                selection: .constant(0), visibleRows: Theme.Size.pillMenuVisibleRows, onActivate: { _ in },
                search: .init(placeholder: "Search…", placement: .top))
        }
    }

    static func renderMenuKeylines() {
        for frosted in [false, true] {
            for notch in [false, true] {
                for actions in [true, false] {
                    renderMenuKeyline(actions: actions, notch: notch, frosted: frosted)
                }
            }
        }
    }

    private static func renderMenuKeyline(actions: Bool, notch: Bool, frosted: Bool) {
        let scene = "1264-\(actions ? "actions" : "pill")-menu-\(notch ? "notch" : "nonotch")"
        let look: IslandLook = frosted ? .frosted : .black
        let onName = "\(scene)-on-\(look.rawValue)"
        let offName = "\(scene)-off-\(look.rawValue)"
        let contentSize = actions ? launcherSize : CGSize(width: menuWidth, height: Theme.Size.panelHeight)
        let size = CGSize(width: contentSize.width + hostedPadding * 2, height: contentSize.height + hostedPadding * 2)
        let leading = actions ? hostedPadding + launcherSize.width - menuInset - menuWidth : hostedPadding
        let pillHeight = notch ? 32 : NotchTheme.Size.islandRest.height
        let row = actions ? size.height - hostedPadding - menuInset - searchSample
            : hostedPadding + pillHeight + menuInset + searchSample
        let on = renderHosted(onName, size: size, desk: true, frosted: frosted) {
            menuScene(actions: actions, notch: notch, frosted: frosted)
        }
        let off = renderHosted(offName, size: size, desk: true, frosted: frosted) {
            menuScene(actions: actions, notch: notch, frosted: frosted)
                .environment(\.islandMenuKeyline, false)
        }
        let onPixels = menuPixels(on, leading: leading, row: row)
        let offPixels = menuPixels(off, leading: leading, row: row)
        let scale = CGFloat(on.pixelsWide) / on.size.width
        let edgePixels = Int(2 * scale)
        let onEdge = onPixels.prefix(edgePixels).max()!
        let offEdge = offPixels.prefix(edgePixels).max()!
        let onBody = onPixels.last!
        let offBody = offPixels.last!
        if actions {
            checkMenu(onEdge >= onBody + 8, onName, "edge \(onEdge), body \(onBody)")
            checkMenu(abs(offEdge - offBody) <= 1, offName, "edge \(offEdge), body \(offBody)")
        } else {
            checkMenu(onEdge >= offEdge + 8, onName, "edge on \(onEdge), off \(offEdge)")
            checkMenu(abs(onBody - offBody) <= 1, onName, "body on \(onBody), off \(offBody)")
        }
        let lit = zip(onPixels, offPixels).map { $0 - $1 >= 8 }
        let expected = Int((IslandKeyline.width(scale: scale, look: look) * scale).rounded())
        checkMenu(lit.prefix(expected).allSatisfy { $0 } && !lit.dropFirst(expected).contains(true),
                  onName, "expected \(expected) outline pixels at the edge, sampled \(onPixels) on and \(offPixels) off")
        print("PASS \(scene)-\(look.rawValue): edge on \(onEdge), off \(offEdge), width \(expected) px")
    }

    @ViewBuilder
    private static func menuScene(actions: Bool, notch: Bool, frosted: Bool) -> some View {
        if actions {
            actionsMenu(notch: notch, frosted: frosted)
        } else {
            pillMenu(notch: notch, frosted: frosted)
        }
    }
}
