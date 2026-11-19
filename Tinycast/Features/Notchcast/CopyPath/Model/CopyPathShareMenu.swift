import Foundation

/// One menu item as Accessibility reports it, reduced to what finding Share needs.
nonisolated struct CopyPathMenuItem: Equatable, Sendable {
    var title: String?
    /// `AXMenuItemCmdChar`; nil when the item has no key equivalent.
    var commandKey: String?
    /// `AXMenuItemCmdModifiers`: 0 is ⌘ alone.
    var modifiers = 0
    var isEnabled = true
    var hasSubmenu = false
}

/// Finds a Gecko browser's File › Share submenu without trusting its localized title first.
nonisolated enum CopyPathShareMenu {
    /// The Share item in one top-level menu: the submenu right after ⌘S (Save Page As…), Gecko's slot.
    static func shareByShortcut(_ items: [CopyPathMenuItem]) -> Int? {
        guard let save = items.firstIndex(where: { $0.commandKey?.lowercased() == "s" && $0.modifiers == 0 }),
            save + 1 < items.count, items[save + 1].hasSubmenu else { return nil }
        return save + 1
    }

    /// The fallback for a browser whose Save Page shortcut was changed: a submenu titled "Share".
    static func shareByTitle(_ items: [CopyPathMenuItem]) -> Int? {
        items.firstIndex { $0.hasSubmenu && $0.title == "Share" }
    }

    /// Share's first item, Copy Link(s); a disabled or missing one is never stood in for by another.
    static func copyLinks(_ items: [CopyPathMenuItem]) -> Int? {
        guard let first = items.first, first.isEnabled, !first.hasSubmenu else { return nil }
        return 0
    }
}
