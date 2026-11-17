import SwiftUI

extension View {
    /// The island hangs Tinycast's own tooltip; a stand-alone surface keeps the system `.help`.
    func paletteHelp(_ text: String, alignment: HorizontalAlignment = .center) -> some View {
        modifier(PaletteHelp(text: text, alignment: alignment))
    }
}

private struct PaletteHelp: ViewModifier {
    let text: String
    let alignment: HorizontalAlignment
    @Environment(\.paletteOnIsland) private var onIsland

    @ViewBuilder func body(content: Content) -> some View {
        if onIsland {
            content.tooltip(text, alignment: alignment, edge: .bottom)
        } else {
            content.help(text)
        }
    }
}
