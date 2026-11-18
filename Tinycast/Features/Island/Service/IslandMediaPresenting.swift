import SwiftUI

/// A song in the wings and a page under the pill; add-ons cast `context.presenter` to reach it.
@MainActor
protocol IslandMediaPresenting: AnyObject {
    /// Nil clears the glance (D8); `onTap` runs on a click on the glancing pill.
    func setMedia(_ media: IslandMedia?, owner: String, onTap: (@MainActor () -> Void)?)
    /// The page hover opens over the owner's glance; nil removes it.
    func setPage(_ page: IslandPage?, owner: String)
    /// A command or a click: opens the page, holds it open and hands it the keyboard (D27).
    func openPage(owner: String)
    func closePage(owner: String)
}

/// An add-on's own island page: its view, its size and the keys it takes while it holds the keyboard.
struct IslandPage {
    let owner: String
    let size: CGSize
    let view: @MainActor () -> AnyView
    /// Returns true when the page used the key; Escape and Command-P stay the island's.
    var onKey: @MainActor (IslandPageKey) -> Bool = { _ in false }
}

enum IslandPageKey: Equatable, Sendable {
    case space, left, right, up, down, refresh
}
