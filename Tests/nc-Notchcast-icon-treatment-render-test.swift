// notchcast-sources: Tinycast/Platform/Appearance.swift Tinycast/DesignSystem/Theme.swift
// notchcast-sources: Tinycast/DesignSystem/InterfaceMetrics.swift Tinycast/Features/Notchcast/NotchTheme.swift
// notchcast-sources: Tinycast/DesignSystem/IconTile.swift
// notchcast-sources: Tinycast/DesignSystem/IconTint.swift Tinycast/Platform/Images/IconCache.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPaletteSurface.swift
import AppKit
import SwiftUI

@MainActor
enum IslandVerification {
    static let stock = false
}

/// #916 design round, prototype only: renders the launcher and Settings rows in each icon treatment
/// offscreen (Dark, 2x) to `NC_ICON_RENDERS`. Nothing here ships.
@MainActor
@main
struct NotchcastIconTreatmentRenderTest {
    static let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["NC_ICON_RENDERS"]
        ?? NSTemporaryDirectory() + "nc-icon-treatment-renders")

    static func write(_ name: String, _ image: CGImage?) {
        guard let image else { preconditionFailure("\(name) did not render") }
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            preconditionFailure("\(name) has no PNG")
        }
        do { try data.write(to: folder.appendingPathComponent("\(name).png")) } catch {
            preconditionFailure("\(name): \(error)")
        }
    }

    /// Drawn straight into an sRGB context: `cgImage` comes back HDR (PQ), lifting every dark value.
    static func render(_ name: String, _ view: some View) -> CGImage? {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
        var image: CGImage?
        renderer.render { size, draw in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: nil, width: Int(size.width * 2), height: Int(size.height * 2),
                                          bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.scaleBy(x: 2, y: 2)
            draw(context)
            image = context.makeImage()
        }
        write(name, image)
        return image
    }

    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var missing: [String] = []
        for row in SampleRow.launcher {
            for symbol in [row.symbol, row.filledSymbol].compactMap({ $0 })
            where NSImage(systemSymbolName: symbol, accessibilityDescription: nil) == nil {
                missing.append(symbol)
            }
        }
        precondition(missing.isEmpty, "not SF Symbols: \(missing)")

        for treatment in Treatment.allCases {
            for look in [false, true] {
                for notch in [false, true] {
                    let name = "launcher-\(treatment.slug)-\(look ? "frosted" : "black")-\(notch ? "notch" : "island")"
                    _ = render(name, LauncherMock(treatment: treatment, frosted: look, notch: notch))
                }
            }
            _ = render("settings-\(treatment.slug)", SettingsMock(treatment: treatment))
        }
        _ = render("sheet", Sheet())
        print("PASS rendered icon treatments to \(folder.path)")
    }
}

// MARK: - Tokens

/// OBSIDIAN's Mac values from the design-system skill's `ObsidianTokens`, until its adoption lands.
enum Obsidian {
    static let foregroundStrong = Color(.sRGB, red: 244 / 255, green: 245 / 255, blue: 247 / 255)
    static let secondary = Color(.sRGB, white: 1, opacity: 0.72)
    static let tertiary = Color(.sRGB, white: 1, opacity: 0.60)
    static let accent = Color(.sRGB, white: 1)
    static let accentDim = Color(.sRGB, white: 1, opacity: 0.08)
    static let glassBar = Color(.sRGB, red: 24 / 255, green: 25 / 255, blue: 28 / 255, opacity: 0.88)
    static let glassEdge = Color(.sRGB, white: 1, opacity: 0.12)
    static let glassRule = Color(.sRGB, white: 1, opacity: 0.16)
    static let glassHover = Color(.sRGB, white: 1, opacity: 0.08)
    static let glassPressed = Color(.sRGB, white: 1, opacity: 0.14)
    static let glassCursor = Color(.sRGB, white: 1, opacity: 0.16)
}

// MARK: - Treatments

enum Treatment: CaseIterable {
    case today, perLook, graphite, bare, glass

    var slug: String {
        switch self {
        case .today: "0-today"
        case .perLook: "a-per-look"
        case .graphite: "b-graphite"
        case .bare: "c-bare-glyph"
        case .glass: "d-glass-tile"
        }
    }

    var title: String {
        switch self {
        case .today: "0: today, upstream's colour tiles"
        case .perLook: "A: per-look wash tile"
        case .graphite: "B: one graphite tile"
        case .bare: "C: bare glyph, no tile"
        case .glass: "D: one glass tile (new)"
        }
    }

    var note: String {
        switch self {
        case .today: "IconTile on 13 saturated gradients; our add-ons graphite with outline glyphs"
        case .perLook: "Black: glassPressed 0.14, no edge. Frosted: glassHover 0.08 + 1 pt glassEdge. Glyph primary"
        case .graphite: "Every tint → upstream's .graphite gradient, white glyph, same pixels on both looks"
        case .bare: "The glyph alone in secondary 0.72; primary on the cursor row"
        case .glass: "glassPressed 0.14 wash + upstream's own top edge light, white glyph. Same on both looks and Settings"
        }
    }

    var glass: String {
        switch self {
        case .today: "Glass: covered by an opaque colour slab per row"
        case .perLook: "Glass: shows through, each tile 92% clear, but every tile is ringed"
        case .graphite: "Glass: covered by an opaque dark slab per row"
        case .bare: "Glass: untouched, nothing is drawn on it"
        case .glass: "Glass: shows through, each tile 86% clear, lit from the top, no ring"
        }
    }

    /// Upstream's pack is filled; our add-ons follow it everywhere except today's shipped state.
    var filledAddons: Bool { self != .today }
}

/// One command icon in a treatment, in the 28 pt slot at an app icon's body size.
struct TreatedIcon: View {
    let treatment: Treatment
    let symbol: String
    let tint: IconTint
    var onCursor = false
    @Environment(\.islandFrosted) private var frosted

    var body: some View {
        switch treatment {
        case .today: IconTile(symbol: symbol, tint: tint, extent: IconCache.appIconBody)
        case .graphite: IconTile(symbol: symbol, tint: .graphite, extent: IconCache.appIconBody)
        case .perLook:
            WashTile(symbol: symbol, ink: Obsidian.foregroundStrong,
                     fill: frosted ? Obsidian.glassHover : Obsidian.glassPressed,
                     edge: frosted ? Obsidian.glassEdge : .clear)
        case .glass:
            WashTile(symbol: symbol, ink: .white, fill: Obsidian.glassPressed, edge: .clear, edgeLight: true)
        case .bare:
            WashTile(symbol: symbol, ink: onCursor ? Obsidian.foregroundStrong : Obsidian.secondary,
                     fill: .clear, edge: .clear)
        }
    }
}

/// `IconTile`'s geometry with a translucent fill, so the surface under the tile stays visible.
struct WashTile: View {
    let symbol: String
    let ink: Color
    let fill: Color
    let edge: Color
    var edgeLight = false

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height) * IconCache.appIconBody
            let shape = RoundedRectangle(cornerRadius: side * IconCache.appIconCornerRatio, style: .continuous)
            Image(systemName: symbol).resizable().scaledToFit()
                .fontWeight(.semibold).fontDesign(.rounded)
                .foregroundStyle(ink)
                .frame(width: side * Theme.IconTile.glyphRatio, height: side * Theme.IconTile.glyphRatio)
                .frame(width: side, height: side)
                .background(fill, in: shape)
                .overlay { shape.strokeBorder(edge, lineWidth: 1) }
                .overlay {
                    if edgeLight {
                        shape.strokeBorder(Theme.IconTile.edgeLight, lineWidth: side * Theme.IconTile.edgeLightRatio)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

// MARK: - Sample rows

struct SampleRow: Identifiable {
    enum Icon { case app(String), tile(String, IconTint) }

    let id = UUID()
    let name: String
    let subtitle: String?
    let kind: String
    let icon: Icon
    var filledSymbol: String?
    var isAddon = false

    var symbol: String? {
        if case .tile(let symbol, _) = icon { return symbol }
        return nil
    }

    static let launcher: [SampleRow] = [
        SampleRow(name: "Safari", subtitle: nil, kind: "Application", icon: .app("/Applications/Safari.app")),
        SampleRow(name: "Clipboard History", subtitle: "Clipboard", kind: "Command",
                  icon: .tile("list.clipboard.fill", .indigo)),
        SampleRow(name: "Join Next Meeting", subtitle: "Calendar", kind: "Command", icon: .tile("video.fill", .red)),
        SampleRow(name: "Capture Area", subtitle: "Notchcast", kind: "Command",
                  icon: .tile("camera.viewfinder", .graphite), filledSymbol: "camera.viewfinder", isAddon: true),
        SampleRow(name: "Restart", subtitle: "System", kind: "Command", icon: .tile("arrow.clockwise", .orange)),
        SampleRow(name: "Generate Password", subtitle: "Notchcast", kind: "Command",
                  icon: .tile("key", .graphite), filledSymbol: "key.fill", isAddon: true),
        SampleRow(name: "Download Video", subtitle: "Notchcast", kind: "Command",
                  icon: .tile("video", .graphite), filledSymbol: "video.fill", isAddon: true),
        SampleRow(name: "Shorten Link", subtitle: "Notchcast", kind: "Command",
                  icon: .tile("link", .graphite), filledSymbol: "link", isAddon: true),
        SampleRow(name: "Run Distill", subtitle: "Notchcast", kind: "Command",
                  icon: .tile("play", .graphite), filledSymbol: "play.fill", isAddon: true),
    ]
}

struct SampleIcon: View {
    let row: SampleRow
    let treatment: Treatment
    var onCursor = false

    var body: some View {
        switch row.icon {
        case .app(let path):
            Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable()
        case .tile(let symbol, let tint):
            let drawn = treatment.filledAddons ? (row.filledSymbol ?? symbol) : symbol
            TreatedIcon(treatment: treatment, symbol: drawn, tint: tint, onCursor: onCursor)
        }
    }
}

// MARK: - Launcher

/// The open launcher on the island: search, rows and the footer capsule, inside the look's outline.
struct LauncherMock: View {
    let treatment: Treatment
    let frosted: Bool
    let notch: Bool
    private let metrics = InterfaceMetrics.standard
    static let notchSize = CGSize(width: 185, height: 32)
    static let margin: CGFloat = 40

    var body: some View {
        let top: CGFloat = notch ? Self.notchSize.height : 0
        let shape = UnevenRoundedRectangle(
            bottomLeadingRadius: Theme.Radius.panel, bottomTrailingRadius: Theme.Radius.panel, style: .continuous)
        VStack(spacing: 0) {
            Color.clear.frame(height: top)
            content
        }
        .frame(width: metrics.size.panelWidth, height: metrics.size.panelHeight + top, alignment: .top)
        .clipShape(shape)
        .background { shape.fill(frosted ? Obsidian.glassBar : Color.black) }
        .overlay {
            // The outline hangs from the screen top, so its edge runs down the sides and along the bottom only.
            shape.strokeBorder(Obsidian.glassEdge, lineWidth: frosted ? 1 : 0.5)
                .padding(.top, -2).clipped()
        }
        .overlay(alignment: .top) {
            if notch {
                UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10)
                    .fill(Color.black)
                    .frame(width: Self.notchSize.width, height: Self.notchSize.height)
            }
        }
        .padding([.horizontal, .bottom], Self.margin)
        .background(Wallpaper(frosted: frosted))
        .environment(\.islandFrosted, frosted)
        .environment(\.paletteOnIsland, true)
        .environment(\.metrics, metrics)
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack(spacing: metrics.spacing.lg) {
                Image(systemName: "magnifyingglass").font(metrics.typography.searchField)
                    .foregroundStyle(Obsidian.tertiary)
                Text("Search for apps and commands…")
                    .font(metrics.typography.searchField)
                    .foregroundStyle(Obsidian.tertiary)
                Spacer()
            }
            .padding(.horizontal, metrics.spacing.xl + metrics.spacing.md)
            .frame(height: metrics.size.compactHeight)
            Rectangle().fill(Obsidian.glassRule).frame(height: Theme.Size.hairline)
            // Nine rows are 2 pt taller than the list: they overflow it as a scrolled list, not the footer.
            Color.clear.overlay(alignment: .top) {
                VStack(spacing: 0) {
                    ForEach(Array(SampleRow.launcher.enumerated()), id: \.offset) { index, row in
                        LauncherRowMock(row: row, treatment: treatment, onCursor: index == 2)
                    }
                }
                .padding(metrics.spacing.md)
            }
            .clipped()
            HStack {
                Spacer()
                HStack(spacing: metrics.spacing.xxs) {
                    footerButton("Open", caps: ["↵"])
                    footerButton("Actions", caps: ["⌘", "K"], secondary: true)
                }
                .padding(metrics.spacing.xs)
                .overlay { Capsule().strokeBorder(frosted ? Obsidian.glassEdge : .clear, lineWidth: 1) }
            }
            .padding(.horizontal, metrics.spacing.md)
            .frame(height: metrics.size.bottomBarHeight)
        }
    }

    private func footerButton(_ title: String, caps: [String], secondary: Bool = false) -> some View {
        HStack(spacing: metrics.spacing.sm) {
            Text(title).font(metrics.typography.bar)
                .foregroundStyle(secondary ? Obsidian.secondary : Obsidian.foregroundStrong)
            HStack(spacing: metrics.spacing.xxs) {
                ForEach(caps, id: \.self) { KeycapMock(text: $0) }
            }
        }
        .padding(.horizontal, metrics.spacing.lg)
        .frame(height: metrics.size.barButtonHeight)
    }
}

/// The island keycap on OBSIDIAN's washes: pressed on Black, hover and an edge on Frosted.
struct KeycapMock: View {
    let text: String
    @Environment(\.islandFrosted) private var frosted
    private let metrics = InterfaceMetrics.standard

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: metrics.radius.keyCap, style: .continuous)
        Text(text).font(metrics.typography.keyCap).foregroundStyle(Obsidian.secondary)
            .padding(.horizontal, metrics.spacing.xs)
            .frame(minWidth: metrics.size.keyCap, minHeight: metrics.size.keyCap)
            .background(frosted ? Obsidian.glassHover : Obsidian.glassPressed, in: shape)
            .overlay { shape.strokeBorder(frosted ? Obsidian.glassEdge : .clear, lineWidth: 1) }
    }
}

struct LauncherRowMock: View {
    let row: SampleRow
    let treatment: Treatment
    let onCursor: Bool
    private let metrics = InterfaceMetrics.standard

    var body: some View {
        // OBSIDIAN: secondary text on the cursor row becomes primary.
        let quiet = onCursor ? Obsidian.foregroundStrong : Obsidian.secondary
        HStack(spacing: metrics.spacing.lg) {
            SampleIcon(row: row, treatment: treatment, onCursor: onCursor)
                .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
            Text(row.name).font(metrics.typography.rowTitle).foregroundStyle(Obsidian.foregroundStrong)
                .lineLimit(1)
            if let subtitle = row.subtitle {
                Text(subtitle).font(metrics.typography.rowTrailing).foregroundStyle(quiet).lineLimit(1)
            }
            Spacer()
            Text(row.kind).font(metrics.typography.rowTrailing).foregroundStyle(quiet)
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(onCursor ? Obsidian.glassCursor : Color.clear,
                    in: RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous))
    }
}

/// Frosted sits over a bright, uneven wallpaper, so glass a tile covers shows as covered.
struct Wallpaper: View {
    let frosted: Bool

    var body: some View {
        if frosted {
            ZStack {
                LinearGradient(colors: [Color(.sRGB, red: 0.93, green: 0.88, blue: 0.80),
                                        Color(.sRGB, red: 0.72, green: 0.80, blue: 0.92)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [Color(.sRGB, red: 1.0, green: 0.52, blue: 0.22), .clear],
                               center: UnitPoint(x: 0.10, y: 0.42), startRadius: 0, endRadius: 230)
                RadialGradient(colors: [Color(.sRGB, red: 0.36, green: 0.42, blue: 0.98), .clear],
                               center: UnitPoint(x: 0.16, y: 0.88), startRadius: 0, endRadius: 210)
            }
        } else {
            Color(.sRGB, white: 0.18)
        }
    }
}

// MARK: - Settings

/// The stock Settings window's dark grouped form: sidebar tab icons and a command list's rows.
struct SettingsMock: View {
    let treatment: Treatment
    private let sidebar: [(String, String, IconTint)] = [
        ("General", "switch.2", .gray), ("Clipboard", "list.clipboard.fill", .indigo),
        ("Calendar", "calendar", .red), ("Notes", "text.page.fill", .yellow),
        ("File Search", "doc.text.magnifyingglass", .blue), ("AI", "sparkles", .purple),
        ("Notchcast", "sparkles.rectangle.stack.fill", .graphite)]
    private let commands: [(String, String, IconTint)] = [
        ("Clipboard History", "list.clipboard.fill", .indigo),
        ("Paste Sequentially", "arrow.right.doc.on.clipboard", .indigo),
        ("Join Next Meeting", "video.fill", .red), ("My Schedule", "calendar", .red)]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach(Array(sidebar.enumerated()), id: \.offset) { index, tab in
                    HStack(spacing: Theme.Spacing.md) {
                        TreatedIcon(treatment: treatment, symbol: tab.1, tint: tab.2)
                            .frame(width: Theme.Size.settingsRowIcon, height: Theme.Size.settingsRowIcon)
                        Text(tab.0).font(.body).foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(index == 1 ? Obsidian.accentDim : .clear,
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            .padding(Theme.Spacing.md)
            .frame(width: 220)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Color(nsColor: .underPageBackgroundColor))
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Commands").font(.headline).foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    ForEach(Array(commands.enumerated()), id: \.offset) { index, command in
                        HStack(spacing: Theme.Spacing.lg) {
                            TreatedIcon(treatment: treatment, symbol: command.1, tint: command.2)
                                .frame(width: Theme.Size.settingsRowIcon + Theme.Spacing.xs,
                                       height: Theme.Size.settingsRowIcon + Theme.Spacing.xs)
                            Text(command.0).font(.body)
                            Spacer()
                            Image(systemName: "checkmark.square.fill").foregroundStyle(Obsidian.accent)
                        }
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.vertical, Theme.Spacing.sm)
                        if index < commands.count - 1 { Divider().padding(.leading, 44) }
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(Theme.Spacing.xxl)
            .frame(width: 440)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(height: 300)
        .environment(\.islandFrosted, false)
    }
}

// MARK: - Sheet

struct Sheet: View {
    private static let side: CGFloat = 290

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("#916 Launcher and Settings icon treatments on OBSIDIAN tokens. Dark, 2x. Full-size PNGs beside this sheet.")
                .font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
            HStack(spacing: 0) {
                ForEach(["Black · no notch", "Black · notch", "Frosted · no notch", "Frosted · notch", "Settings (no look)"],
                        id: \.self) { label in
                    Text(label).font(.system(size: 16, weight: .medium)).foregroundStyle(.white.opacity(0.72))
                        .frame(width: label.hasPrefix("Settings") ? 330 : 415, alignment: .leading)
                }
            }
            .padding(.leading, Self.side + 15)
            ForEach(Array(Treatment.allCases.enumerated()), id: \.offset) { _, treatment in
                HStack(alignment: .top, spacing: 15) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(treatment.title).font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(treatment.note).font(.system(size: 12)).foregroundStyle(.white.opacity(0.72))
                        Text(treatment.glass).font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                        Text("Close-up at full size, Black then Frosted").font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.6))
                        closeUp(treatment, frosted: false)
                        closeUp(treatment, frosted: true)
                    }
                    .frame(width: Self.side, alignment: .leading)
                    cell(treatment, frosted: false, notch: false)
                    cell(treatment, frosted: false, notch: true)
                    cell(treatment, frosted: true, notch: false)
                    cell(treatment, frosted: true, notch: true)
                    SettingsMock(treatment: treatment).scaleEffect(0.5, anchor: .topLeading)
                        .frame(width: 330, height: 150, alignment: .topLeading)
                }
            }
        }
        .padding(32)
        .background(Color(.sRGB, white: 0.08))
    }

    /// Every command icon of the launcher sample at its real 28 pt slot, for judging the glyphs.
    private func closeUp(_ treatment: Treatment, frosted: Bool) -> some View {
        let rows = SampleRow.launcher.filter { $0.symbol != nil }
        return HStack(spacing: Theme.Spacing.xs) {
            ForEach(rows) { row in
                SampleIcon(row: row, treatment: treatment)
                    .frame(width: Theme.Size.resultRowIcon, height: Theme.Size.resultRowIcon)
            }
        }
        .padding(Theme.Spacing.sm)
        .background(frosted ? Obsidian.glassBar : Color.black)
        .background(Wallpaper(frosted: frosted))
        .environment(\.islandFrosted, frosted)
    }

    private func cell(_ treatment: Treatment, frosted: Bool, notch: Bool) -> some View {
        LauncherMock(treatment: treatment, frosted: frosted, notch: notch)
            .scaleEffect(0.48, anchor: .topLeading)
            .frame(width: 400, height: 270, alignment: .topLeading)
    }
}
