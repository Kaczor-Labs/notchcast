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

    /// One page shows alone, with no tab bar; two or more get Home first; none, an empty Home.
    var tabs: [Tab] {
        switch pages.count {
        case 0: [.home]
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

    /// What the resting island shows heads the open page on every tab, so a page never hides it.
    private(set) var notice: IslandPageRow?

    /// The notice row's id when it has a tap; the host routes it like a page's action.
    static let noticeID = "island.notice"

    mutating func show(_ notice: IslandNotice?, tappable: Bool) {
        self.notice = notice.map {
            IslandPageRow(id: tappable ? Self.noticeID : nil, symbol: $0.symbol, title: $0.line, spoken: $0.spokenText)
        }
    }

    /// With a page, a click on the resting island opens it; the notice's own tap moves to its row.
    var opensOnClick: Bool { !pages.isEmpty }

    /// Hover or a pin opens the pages while one exists, and Home on a bare island (#884, #975).
    func opens(glance: Bool) -> Bool { !pages.isEmpty || (notice == nil && !glance) }

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

    /// The shown page's own action for `key` when that page takes keys; otherwise the deck keeps the key.
    func pageAction(for key: IslandPageKey) -> (page: String, action: String)? {
        guard let page = current, page.takesKeys, let action = key.action else { return nil }
        return (page.id, action)
    }

    /// Whether `id`'s data is on show: on Home, on its own page, or with no page yet, so it can post one.
    func shows(_ id: String) -> Bool {
        guard page(id) != nil, case .page(let shown)? = selection else { return true }
        return shown == id
    }

    /// The island's outline for content of `size`: at least the rest pill, past a notch by one radius a side.
    static func outline(content size: CGSize, rest: CGSize, notch: CGFloat?, radius: CGFloat,
                        maxHeight: CGFloat) -> CGSize {
        let floor = max(rest.width, notch.map { $0 + 2 * radius } ?? 0)
        return CGSize(width: max(size.width, floor).rounded(.up),
                      height: min(max(size.height, rest.height), maxHeight).rounded(.up))
    }
}

/// Tells each watcher once when its data comes on show and once when it goes (decision 946, refresh).
struct IslandPageAudience: Equatable, Sendable {
    private var seeing: Set<String> = []

    mutating func changes(watchers: [String], open: Bool, deck: IslandPageDeck) -> [(id: String, visible: Bool)] {
        let next = Set(open ? watchers.filter(deck.shows) : [])
        let changed = watchers.filter { seeing.contains($0) != next.contains($0) }
        seeing = next
        return changed.map { ($0, next.contains($0)) }
    }

    mutating func forget(_ id: String) { seeing.remove(id) }
}

/// The panel takes key once a pin begins, never on a repost while pinned (#1005 review, finding 2).
struct IslandPageFocus: Equatable, Sendable {
    private var pinned = false

    mutating func takesKey(pinned: Bool) -> Bool {
        defer { self.pinned = pinned }
        return pinned && !self.pinned
    }
}

/// What a key does on a pinned page: arrows, space, 1–9 and Escape bare; R and P only with Command.
enum IslandPageKey: Equatable, Sendable {
    case move(Int)
    case number(Int)
    case close
    case refresh
    case pin
    case space
    /// Up is 1, down -1; only a page that takes keys uses them.
    case step(Int)

    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126
    static let spaceBar: UInt16 = 49
    static let escape: UInt16 = 53

    /// A held ↑ or ↓ keeps stepping the volume; a held arrow or space acts once per press, never per repeat.
    var repeatsOnPage: Bool { if case .step = self { true } else { false } }

    /// What a page that takes keys gets for this key instead of the deck; nil keeps it the deck's.
    var action: String? {
        switch self {
        case .move(-1): "key.left"
        case .move(1): "key.right"
        case .step(1): "key.up"
        case .step(-1): "key.down"
        case .space: "key.space"
        default: nil
        }
    }

    init?(keyCode: UInt16, characters: String, command: Bool) {
        switch (command, keyCode, characters.lowercased()) {
        case (true, _, "r"): self = .refresh
        case (true, _, "p"): self = .pin
        case (false, Self.leftArrow, _): self = .move(-1)
        case (false, Self.rightArrow, _): self = .move(1)
        case (false, Self.upArrow, _): self = .step(1)
        case (false, Self.downArrow, _): self = .step(-1)
        case (false, Self.spaceBar, _): self = .space
        case (false, Self.escape, _): self = .close
        default:
            guard !command, let number = Int(characters), (1...9).contains(number) else { return nil }
            self = .number(number)
        }
    }
}
