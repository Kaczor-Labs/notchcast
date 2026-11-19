import SwiftUI

/// The open island's pages: tabs while two or more exist, then Home or the chosen page (#975).
struct IslandPagesView: View {
    let deck: IslandPageDeck
    let select: (IslandPageDeck.Tab) -> Void
    /// A button or row on a page: the page's id, then the action's.
    let act: (String, String) -> Void
    @Environment(\.metrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.md) {
            if deck.showsTabBar {
                HStack(spacing: metrics.spacing.xs) {
                    ForEach(deck.tabs, id: \.self) { tab($0) }
                }
            }
            if let page = deck.current {
                IslandPageBody(blocks: page.blocks) { act(page.id, $0) }
            } else {
                VStack(spacing: metrics.spacing.xxs) {
                    ForEach(deck.homeLines, id: \.id) { page in
                        IslandPageLineView(line: page.line, open: { select(.page(page.id)) }, act: { act(page.id, $0) })
                    }
                }
            }
        }
        .padding(metrics.spacing.md)
        .fixedSize()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func tab(_ tab: IslandPageDeck.Tab) -> some View {
        let page: IslandPage? = if case .page(let id) = tab { deck.page(id) } else { nil }
        let title = page?.title ?? String(localized: "Home")
        let badge = page?.badge ?? 0
        let selected = tab == deck.selection
        return BarButton(isSelected: selected, action: { select(tab) }) {
            HStack(spacing: metrics.spacing.xs) {
                SymbolImage(name: page?.symbol ?? "house", size: metrics.scaled(Theme.Typography.menuSymbolSize),
                            monochrome: true)
                Text(title).font(metrics.typography.bar)
                if badge > 0 { KeyCapChip(text: "\(badge)", style: .outline, scale: .compact) }
            }
            .foregroundStyle(selected ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(badge > 0 ? "\(badge)" : "")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A Home line: the page summed up; a click opens its tab, its own buttons act in place.
struct IslandPageLineView: View {
    let line: IslandPageLine
    let open: () -> Void
    let act: (String) -> Void
    @Environment(\.metrics) private var metrics
    @State private var hovered = false

    var body: some View {
        HStack(spacing: metrics.spacing.xs) {
            Button(action: open) {
                IslandPageLabel(symbol: line.symbol, artwork: line.artwork, title: line.text, detail: line.detail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            ForEach(line.buttons, id: \.id) { button in
                IslandPageIconButton(button: button) { act(button.id) }
            }
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.xs)
        .background(RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
            .fill(hovered ? Theme.Colors.rowHover : Color.clear))
        .onHover { hovered = $0 }
    }
}

/// A glyph or artwork in a row-icon slot beside one title and an optional detail line.
struct IslandPageLabel: View {
    let symbol: String?
    let artwork: Data?
    let title: String
    let detail: String?
    @Environment(\.metrics) private var metrics

    var body: some View {
        HStack(spacing: metrics.spacing.md) {
            IslandPageArtwork(symbol: symbol, artwork: artwork, side: metrics.size.resultRowIcon)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(metrics.typography.rowTitle).foregroundStyle(Theme.Colors.textPrimary)
                if let detail {
                    Text(detail).font(metrics.typography.rowTrailing).foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: NotchTheme.Size.islandHeadlineMaxWidth, alignment: .leading)
        }
    }
}

/// Artwork that decodes, else the glyph, in a square `side` points wide.
struct IslandPageArtwork: View {
    let symbol: String?
    let artwork: Data?
    let side: CGFloat
    var radius: CGFloat?
    @Environment(\.metrics) private var metrics

    var body: some View {
        Group {
            if let image = artwork.flatMap(NSImage.init(data:)) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: radius ?? metrics.radius.thumbnail, style: .continuous))
                    .accessibilityHidden(true)
            } else if let symbol {
                SymbolImage(name: symbol, size: metrics.scaled(Theme.Typography.menuSymbolSize), monochrome: true)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .frame(width: side, height: side)
    }
}

/// A bare icon button: `rowHover`, `keyCapFill` on press (design §7), named for VoiceOver and the tooltip.
struct IslandPageIconButton: View {
    let button: IslandPageButton
    let action: () -> Void
    @Environment(\.metrics) private var metrics

    var body: some View {
        BarButton(isCompact: true, action: action) {
            SymbolImage(name: button.symbol, size: metrics.scaled(Theme.Typography.menuSymbolSize), monochrome: true)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .accessibilityLabel(button.label)
        .tooltip(button.label)
    }
}
