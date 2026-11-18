import CoreGraphics
import Foundation

/// Which tabs the open island holds and which one shows (#975, decisions 946-1, 946-2, 946-6).
struct IslandPageDeck: Equatable, Sendable {
    enum Tab: Hashable, Sendable {
        case home
        case page(String)
    }

    /// Only pages whose module is on and has data: an owner removes its page when it has none.
    private(set) var pages: [IslandPage] = []
    private var chosen: Tab?

    mutating func set(_ page: IslandPage?, id: String) {
        pages.removeAll { $0.id == id }
        if var page {
            page.id = id
            pages.append(page)
            pages.sort { ($0.order, $0.id) < ($1.order, $1.id) }
        }
    }

    /// One page shows alone, with no Home and no tab bar; two or more get Home first.
    var tabs: [Tab] {
        switch pages.count {
        case 0: []
        case 1: [.page(pages[0].id)]
        default: [.home] + pages.map { .page($0.id) }
        }
    }

    var showsTabBar: Bool { tabs.count > 1 }

    /// The chosen tab while it still exists, else the first: Home, or the single page.
    var selection: Tab? { chosen.flatMap { tabs.contains($0) ? $0 : nil } ?? tabs.first }

    var current: IslandPage? {
        guard case .page(let id)? = selection else { return nil }
        return page(id)
    }

    func page(_ id: String) -> IslandPage? { pages.first { $0.id == id } }

    /// Home lists every page; one waiting for the user comes first (agents before the player).
    var homeLines: [IslandPage] {
        pages.filter { $0.badge > 0 } + pages.filter { $0.badge <= 0 }
    }

    /// Hover always opens on the first tab, never where the last visit left off.
    mutating func open() { chosen = nil }

    mutating func select(_ tab: Tab) {
        if tabs.contains(tab) { chosen = tab }
    }

    /// 1–9 pick a tab by place; a number past the last tab does nothing.
    mutating func select(number: Int) {
        let all = tabs
        if all.indices.contains(number - 1) { chosen = all[number - 1] }
    }

    /// Arrows and swipes move one tab and stop at either end, as page dots do.
    mutating func move(by step: Int) {
        let all = tabs
        guard let selection, let index = all.firstIndex(of: selection) else { return }
        chosen = all[min(max(index + step, 0), all.count - 1)]
    }

    /// The island's outline for content of `size`: at least the rest pill, past a notch by one radius a side.
    static func outline(content size: CGSize, rest: CGSize, notch: CGFloat?, radius: CGFloat,
                        maxHeight: CGFloat) -> CGSize {
        let floor = max(rest.width, notch.map { $0 + 2 * radius } ?? 0)
        return CGSize(width: max(size.width, floor).rounded(.up),
                      height: min(max(size.height, rest.height), maxHeight).rounded(.up))
    }
}

/// What a key does on a pinned page: arrows, 1–9 and Escape bare; R and P only with Command.
enum IslandPageKey: Equatable, Sendable {
    case move(Int)
    case number(Int)
    case close
    case refresh
    case pin

    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let escape: UInt16 = 53

    init?(keyCode: UInt16, characters: String, command: Bool) {
        switch (command, keyCode, characters.lowercased()) {
        case (true, _, "r"): self = .refresh
        case (true, _, "p"): self = .pin
        case (false, Self.leftArrow, _): self = .move(-1)
        case (false, Self.rightArrow, _): self = .move(1)
        case (false, Self.escape, _): self = .close
        default:
            guard !command, let number = Int(characters), (1...9).contains(number) else { return nil }
            self = .number(number)
        }
    }
}
