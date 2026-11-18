// notchcast-sources: Tinycast/Platform/Appearance.swift Tinycast/DesignSystem/Theme.swift
// notchcast-sources: Tinycast/DesignSystem/InterfaceMetrics.swift Tinycast/Features/Notchcast/NotchTheme.swift
// notchcast-sources: Tinycast/DesignSystem/KeyCapChip.swift Tinycast/DesignSystem/IconTile.swift
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

// MARK: - Treatments

enum Treatment: CaseIterable {
    case today, perLook, graphite, bare

    var slug: String {
        switch self {
        case .today: "0-today"
        case .perLook: "a-per-look"
        case .graphite: "b-graphite"
        case .bare: "c-bare-glyph"
        }
    }

    var title: String {
        switch self {
        case .today: "Today: upstream's colour tiles"
        case .perLook: "A: per-look keycap tile"
        case .graphite: "B: one graphite tile"
        case .bare: "C: bare glyph, no tile"
        }
    }

    var note: String {
        switch self {
        case .today: "IconTile + Theme.IconTile.fill(tint), 13 colours; our add-ons graphite, outline glyphs"
        case .perLook: "Black: keyCapFill (white 0.14), textPrimary glyph. Frosted: controlFill 0.07 + controlEdge, glass shows"
        case .graphite: "Every tint → Theme.IconTile.fill(.graphite) + edgeLight, white glyph, same on both looks"
        case .bare: "design-system §6 read literally: glyph in textSecondary at the 28 pt slot, no tile"
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

    var body: some View {
        switch treatment {
        case .today: IconTile(symbol: symbol, tint: tint, extent: IconCache.appIconBody)
        case .graphite: IconTile(symbol: symbol, tint: .graphite, extent: IconCache.appIconBody)
        case .perLook: KeycapTile(symbol: symbol)
        case .bare:
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height) * IconCache.appIconBody
                Image(systemName: symbol).resizable().scaledToFit()
                    .fontWeight(.semibold).fontDesign(.rounded)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(width: side * Theme.IconTile.glyphRatio, height: side * Theme.IconTile.glyphRatio)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }
}

/// Option A: the island keycap's own recipe, which already resolves per look.
struct KeycapTile: View {
    let symbol: String

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height) * IconCache.appIconBody
            let shape = RoundedRectangle(cornerRadius: side * IconCache.appIconCornerRatio, style: .continuous)
            Image(systemName: symbol).resizable().scaledToFit()
                .fontWeight(.semibold).fontDesign(.rounded)
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(width: side * Theme.IconTile.glyphRatio, height: side * Theme.IconTile.glyphRatio)
                .frame(width: side, height: side)
                .background(NotchTheme.Colors.keyCapFill, in: shape)
                .overlay { shape.strokeBorder(NotchTheme.Colors.controlEdge, lineWidth: Theme.Size.hairline) }
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

    var body: some View {
        switch row.icon {
        case .app(let path):
            Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable()
        case .tile(let symbol, let tint):
            let drawn = treatment.filledAddons ? (row.filledSymbol ?? symbol) : symbol
            TreatedIcon(treatment: treatment, symbol: drawn, tint: tint)
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
        .background {
            if frosted {
                shape.fill(NotchTheme.Colors.islandGlassTint)
            } else {
                shape.fill(NotchTheme.Colors.islandSurface)
            }
        }
        .overlay {
            // The outline hangs from the screen top, so its edge runs down the sides and along the bottom only.
            shape.strokeBorder(frosted ? NotchTheme.Colors.islandEdge : NotchTheme.Colors.islandKeyline,
                               lineWidth: frosted ? 1 : 0.5)
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
                    .foregroundStyle(Theme.Colors.textTertiary)
                Text("Search for apps and commands…")
                    .font(metrics.typography.searchField)
                    .foregroundStyle(Theme.Colors.textTertiary)
                Spacer()
            }
            .padding(.horizontal, metrics.spacing.xl + metrics.spacing.md)
            .frame(height: metrics.size.compactHeight)
            Rectangle().fill(NotchTheme.Colors.keyCapFill).frame(height: Theme.Size.hairline)
            VStack(spacing: 0) {
                ForEach(Array(SampleRow.launcher.enumerated()), id: \.offset) { index, row in
                    LauncherRowMock(row: row, treatment: treatment, selected: index == 2, slot: index)
                }
            }
            .padding(metrics.spacing.md)
            .frame(maxHeight: .infinity, alignment: .top)
            .clipped()
            HStack {
                Spacer()
                HStack(spacing: metrics.spacing.xxs) {
                    footerButton("Open", caps: ["↵"])
                    footerButton("Actions", caps: ["⌘", "K"], secondary: true)
                }
                .padding(metrics.spacing.xs)
            }
            .padding(.horizontal, metrics.spacing.md)
            .frame(height: metrics.size.bottomBarHeight)
        }
    }

    private func footerButton(_ title: String, caps: [String], secondary: Bool = false) -> some View {
        HStack(spacing: metrics.spacing.sm) {
            Text(title).font(metrics.typography.bar)
                .foregroundStyle(secondary ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
            ForEach(caps, id: \.self) { KeyCapChip(text: $0, style: .outline) }
        }
        .padding(.horizontal, metrics.spacing.lg)
        .frame(height: metrics.size.barButtonHeight)
    }
}

struct LauncherRowMock: View {
    let row: SampleRow
    let treatment: Treatment
    let selected: Bool
    let slot: Int
    private let metrics = InterfaceMetrics.standard

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            SampleIcon(row: row, treatment: treatment)
                .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
            Text(row.name).font(metrics.typography.rowTitle).foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
            if let subtitle = row.subtitle {
                Text(subtitle).font(metrics.typography.rowTrailing).foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(row.kind).font(metrics.typography.rowTrailing).foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(selected ? Theme.Colors.selection : Color.clear,
                    in: RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous))
        .environment(\.islandInkLifted, selected)
    }
}

/// Black sits under a dark menu-bar desk; Frosted over a bright wallpaper, as the audit renders it.
struct Wallpaper: View {
    let frosted: Bool

    var body: some View {
        if frosted {
            LinearGradient(colors: [Color(.sRGB, red: 0.93, green: 0.88, blue: 0.80),
                                    Color(.sRGB, red: 0.72, green: 0.80, blue: 0.92)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
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
        ("General", "gearshape.fill", .gray), ("Clipboard", "list.clipboard.fill", .indigo),
        ("Calendar", "calendar", .red), ("Notes", "text.page.fill", .yellow),
        ("Window Management", "macwindow", .mint), ("AI", "sparkles", .purple),
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
                    .background(index == 1 ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.35) : .clear,
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
                            Image(systemName: "checkmark.square.fill").foregroundStyle(Color.accentColor)
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
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("#916 Launcher and Settings icon treatments. Dark, 2x. Full-size PNGs beside this sheet.")
                .font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
            HStack(spacing: 0) {
                ForEach(["Black · no notch", "Black · notch", "Frosted · no notch", "Frosted · notch", "Settings (no look)"],
                        id: \.self) { label in
                    Text(label).font(.system(size: 16, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                        .frame(width: label.hasPrefix("Settings") ? 330 : 415, alignment: .leading)
                }
            }
            .padding(.leading, 200)
            ForEach(Array(Treatment.allCases.enumerated()), id: \.offset) { index, treatment in
                HStack(alignment: .top, spacing: 15) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(treatment.title).font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(treatment.note).font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                        Text("Close-up, Black then Frosted").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                        closeUp(treatment, frosted: false)
                        closeUp(treatment, frosted: true)
                    }
                    .frame(width: 185, alignment: .leading)
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
        .background(frosted ? NotchTheme.Colors.islandGlassTint : NotchTheme.Colors.islandSurface)
        .background(Wallpaper(frosted: frosted))
        .environment(\.islandFrosted, frosted)
        .scaleEffect(0.75, anchor: .topLeading)
        .frame(width: 185, height: 30, alignment: .topLeading)
    }

    private func cell(_ treatment: Treatment, frosted: Bool, notch: Bool) -> some View {
        LauncherMock(treatment: treatment, frosted: frosted, notch: notch)
            .scaleEffect(0.48, anchor: .topLeading)
            .frame(width: 400, height: 270, alignment: .topLeading)
    }
}
