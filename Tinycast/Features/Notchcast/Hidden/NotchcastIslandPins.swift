import SwiftUI

// The values the hidden island settings always read; notchcast/docs/hidden.md.
enum NotchcastIslandPins {
    /// Stock colours resolve from `NSAppearance`, so Light or System would put black text on the island.
    static let appearance = AppAppearance.dark
    static let paletteDraggable = false
    static let openOnCursorScreen = true
    static let remembersPalettePosition = false
}

extension View {
    /// A Settings row the island makes meaningless; `NotchcastHidden.rows` keeps it out of search.
    func notchcastHidden() -> some View { EmptyView() }
}
