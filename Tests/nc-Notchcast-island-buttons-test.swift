// notchcast-hosted-only
// notchcast-sources: Tinycast/DesignSystem/BarButton.swift Tinycast/DesignSystem/ModalActionButtonStyle.swift
// notchcast-sources: Tinycast/Windows/Dialog/DialogChip.swift Tinycast/Features/Notchcast/IslandButtonFill.swift
// notchcast-sources: Tinycast/DesignSystem/Theme.swift Tinycast/Platform/Appearance.swift
// notchcast-sources: Tinycast/DesignSystem/InterfaceMetrics.swift
// notchcast-sources: Tinycast/DesignSystem/Tooltip.swift Tinycast/DesignSystem/KeyCapChip.swift Tinycast/Platform/Images/IconCache.swift
import AppKit
import SwiftUI

// Stand-ins for the menu icon types in PopoverMenu.swift, which drags in the whole palette.
enum PopoverMenuIcon: Equatable {
    case blank, symbol(String), asset(String), file(String), thumbnail(id: String, data: Data)
}
struct MenuFileIcon: View { let path: String; var body: some View { EmptyView() } }
struct MenuThumbnail: View { let id: String; let data: Data; var body: some View { EmptyView() } }

@MainActor
@main
struct IslandButtonsTest {
    typealias Pixel = [Double]

    /// The centre pixel of the view on the island's black, the way a dialog or the palette seats it.
    static func centre(of view: some View, onIsland: Bool) -> Pixel {
        let seated = view
            .padding(12)
            .background(Color.black)
            .environment(\.paletteOnIsland, onIsland)
            .environment(\.colorScheme, .dark)
        guard let image = ImageRenderer(content: seated).cgImage else { preconditionFailure("view did not render") }
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let colour = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB)
        else { preconditionFailure("no pixel") }
        return [colour.redComponent, colour.greenComponent, colour.blueComponent]
    }

    static func paint(_ colour: Color) -> Pixel {
        centre(of: Rectangle().fill(colour).frame(width: 40, height: 20), onIsland: true)
    }

    static func same(_ a: Pixel, _ b: Pixel) -> Bool { zip(a, b).allSatisfy { abs($0 - $1) < 0.02 } }

    static func bare(_ pixel: Pixel) -> Bool { pixel.reduce(0, +) < 0.02 }

    static var blank: some View { Color.clear.frame(width: 60, height: 12) }

    static func barButton(selected: Bool, onIsland: Bool) -> Pixel {
        centre(of: BarButton(isSelected: selected, action: {}) { blank }, onIsland: onIsland)
    }

    static func modal(_ role: ModalActionButtonStyle.Role, onIsland: Bool) -> Pixel {
        centre(of: Button(action: {}) { blank }.buttonStyle(.modalAction(role, fillsWidth: false)), onIsland: onIsland)
    }

    static func chip(selected: Bool, onIsland: Bool) -> Pixel {
        centre(of: DialogChip(title: "", selected: selected, onTap: {}), onIsland: onIsland)
    }

    static func main() {
        _ = NSApplication.shared
        let cap = paint(NotchTheme.Colors.keyCapFill)
        let hover = paint(Theme.Colors.rowHover)
        let selection = paint(Theme.Colors.selection)
        let surface = paint(Theme.Colors.controlSurface)
        precondition(!bare(cap) && !bare(hover) && !same(cap, hover) && !same(cap, selection),
                     "keyCapFill, rowHover and selection must be three different fills")

        precondition(bare(IslandButtonFill.neutral(hovered: false).pixel), "rest is bare")
        precondition(same(IslandButtonFill.neutral(hovered: true).pixel, hover), "hover is rowHover")
        precondition(same(IslandButtonFill.neutral(pressed: true, hovered: true).pixel, cap), "pressed is keyCapFill")
        precondition(same(IslandButtonFill.neutral(selected: true, hovered: true).pixel, cap), "selected is keyCapFill")

        precondition(bare(barButton(selected: false, onIsland: true)), "island BarButton is bare at rest")
        precondition(same(barButton(selected: true, onIsland: true), cap), "island BarButton selected is keyCapFill")
        for role in [ModalActionButtonStyle.Role.standard, .cancel] {
            precondition(bare(modal(role, onIsland: true)), "island neutral modal button \(role) is bare at rest")
            precondition(same(modal(role, onIsland: false), surface), "stock modal button \(role) keeps controlSurface")
        }
        precondition(!bare(modal(.primary, onIsland: true)), "a role button keeps its tint")
        precondition(!bare(modal(.destructive, onIsland: true)), "a destructive button keeps its tint")
        precondition(bare(chip(selected: false, onIsland: true)), "island DialogChip is bare at rest")
        precondition(same(chip(selected: true, onIsland: true), cap), "island DialogChip selected is keyCapFill")
        precondition(same(chip(selected: false, onIsland: false), surface), "stock DialogChip keeps controlSurface")
        precondition(same(chip(selected: true, onIsland: false), selection), "stock DialogChip selected keeps selection")

        precondition(bare(barButton(selected: false, onIsland: false)), "stock BarButton is bare at rest")
        precondition(same(barButton(selected: true, onIsland: false), selection), "stock BarButton selected keeps selection")
        precondition(NotchTheme.Opacity.disabled == 0.45, "disabled opacity keeps upstream's value")
        print("PASS island buttons: bare, rowHover, keyCapFill on select and press; roles keep tint; stock unchanged")
    }
}

private extension Color {
    @MainActor var pixel: IslandButtonsTest.Pixel { IslandButtonsTest.paint(self) }
}
