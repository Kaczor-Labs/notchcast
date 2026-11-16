import SwiftUI

/// Island menu text inks (design-system §6); the debug stock comparison keeps the system label colours.
enum NotchMenuInk {
    static func primary(onIsland: Bool) -> Color { onIsland ? Theme.Colors.textPrimary : .primary }
    static func secondary(onIsland: Bool) -> Color { onIsland ? Theme.Colors.textSecondary : .secondary }
}
