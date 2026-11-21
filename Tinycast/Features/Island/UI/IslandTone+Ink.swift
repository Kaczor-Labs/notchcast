import AppKit
import SwiftUI

extension IslandTone {
    /// The status token a tone stands for, which resolves per look like every island ink.
    var color: Color {
        switch self {
        case .warning: Theme.Colors.warning
        case .critical: Theme.Colors.destructive
        }
    }

    func ink(frosted: Bool) -> NSColor { color.islandInk(frosted: frosted) }
}
