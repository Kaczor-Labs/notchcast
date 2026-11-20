// notchcast-hosted-only
// notchcast-sources: Tinycast/Platform/Appearance.swift Tinycast/DesignSystem/Theme.swift
// notchcast-sources: Tinycast/DesignSystem/InterfaceMetrics.swift Tinycast/Features/Notchcast/NotchTheme.swift
// notchcast-sources: Tinycast/DesignSystem/KeyCapChip.swift Tinycast/DesignSystem/BarButton.swift
// notchcast-sources: Tinycast/DesignSystem/SymbolImage.swift Tinycast/DesignSystem/Tooltip.swift
// notchcast-sources: Tinycast/Features/Notchcast/IslandButtonFill.swift Tinycast/Platform/Images/IconCache.swift
// notchcast-sources: Tinycast/Features/Notchcast/NotchMenuInk.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPaletteSurface.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandLook.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPageDeck.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPageSwipe.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPlayer.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandCardSlots.swift
// notchcast-sources: Tinycast/Features/Island/UI/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Agents/Model/*.swift
import AppKit
import SwiftUI

// Stand-ins for the menu icon types in PopoverMenu.swift, which drags in the whole palette.
enum PopoverMenuIcon: Equatable {
    case blank, symbol(String), asset(String), file(String), thumbnail(id: String, data: Data)
}
struct MenuFileIcon: View { let path: String; var body: some View { EmptyView() } }
struct MenuThumbnail: View { let id: String; let data: Data; var body: some View { EmptyView() } }

/// #1189: the MBP's board from the real path, feed to page, in both forms, Black and Frosted.
/// `NC_AUDIT_RENDERS` names the folder, else the audit harness's own, which CI uploads.
@MainActor
@main
struct AgentsBoardRenderTest {
    static let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["NC_AUDIT_RENDERS"]
        ?? NSTemporaryDirectory() + "nc-island-audit-renders")
    static let notchSize = CGSize(width: 185, height: 32)
    static let margin: CGFloat = 32
    static let now = Date(timeIntervalSince1970: 1_795_111_200)  // 2026-11-19 18:00 UTC
    static let home = URL(fileURLWithPath: "/home/tester")

    static func main() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let before = try board(folders: false)
        let after = try board(folders: true)
        precondition(after.columns.first { $0.title == "MBP" }?.cards.map(\.title) == ["C3", "C4"],
                     "this Mac's two folders are the gate's two cards")
        let antigravity = after.other.first { $0.title == "Antigravity" }
        guard case .meters(let meters)? = antigravity?.body else { preconditionFailure("Antigravity has meters") }
        precondition(meters.count == AgentBoard.meterCap && antigravity?.caption == "2 more, lowest 100% left",
                     "five windows show as three meters and one line")
        var heights: [String: CGFloat] = [:]
        for frosted in [false, true] {
            for notch in [false, true] {
                let suffix = "\(notch ? "notch" : "island")-\(frosted ? "frosted" : "black")"
                for (name, board) in [("before", before), ("after", after)] {
                    heights[name] = render("1189-agents-\(name)-\(suffix)", deck: deck(board), notch: notch,
                                           frosted: frosted).height
                }
            }
        }
        // The host caps the open island here, so anything taller is cut at the bottom (#1189 item 3).
        let cap = NotchTheme.Size.islandHost.height - notchSize.height
        print("board heights: before \(heights["before"]!), after \(heights["after"]!), cap \(cap)")
        precondition(heights["after"]! <= cap, "the board fits the island under a notch")
        print("PASS rendered the Agents board to \(folder.path)")
    }

    /// The MBP as the #1128 tester had it: Settings' default names, one stored with Add…'s trailing slash.
    static func board(folders: Bool) throws -> AgentBoard {
        func claude(_ name: String, _ folder: String, _ session: Int, _ weekly: Int, _ fable: Int) -> String {
            let folder = folders ? #""folder": "\#(folder)", "# : ""
            return #"{"name": "\#(name)", "provider": "claude", \#(folder)"checkedAt": "2026-11-19T17:55:00Z", "#
                + #""state": "ok", "windows": [\#(window("session", nil, session, "2026-11-19T20:40:00Z")), "#
                + #"\#(window("weekly", nil, weekly, "2026-11-25T06:00:00Z")), "#
                + #"\#(window("weekly", "Fable", fable, "2026-11-25T06:00:00Z"))]}"#
        }
        func window(_ kind: String, _ scope: String?, _ used: Int, _ resets: String) -> String {
            let scope = scope.map { #""\#($0)""# } ?? "null"
            return #"{"kind": "\#(kind)", "scope": \#(scope), "usedPercent": \#(used), "resetsAt": "\#(resets)"}"#
        }
        func spent(_ name: String, _ provider: String) -> String {
            #"{"name": "\#(name)", "provider": "\#(provider)", "checkedAt": "2026-11-19T17:55:00Z", "state": "ok", "#
                + #""windows": [\#(window("weekly", nil, 100, "2026-11-21T06:00:00Z"))]}"#
        }
        let gemini = [window("weekly", "gemini", 97, "2026-11-26T10:54:00Z"),
                      window("session", "gemini", 38, "2026-11-19T21:17:00Z"),
                      window("weekly", "3p", 0, "2026-11-26T18:00:00Z"), window("session", "3p", 0, "2026-11-19T22:49:00Z"),
                      window("weekly", "gemini-argon-wtu", 0, "2026-11-26T18:00:00Z")].joined(separator: ", ")
        let json = #"{"version": 1, "generatedAt": "2026-11-19T17:59:00Z", "machines": ["#
            + #"{"name": "MBA", "accounts": [\#(claude("C1", "~/.claude", 10, 93, 83)), \#(claude("C2", "~/.claude_team", 24, 69, 100))]}, "#
            + #"{"name": "MBP", "accounts": [\#(claude("C3", "~/.claude", 3, 50, 76)), \#(claude("C4", "~/.claude_team", 24, 67, 85))]}, "#
            + #"{"name": "VPS", "accounts": [\#(claude("C5", "~/.claude", 3, 8, 4)), \#(claude("C6", "~/.claude_team", 1, 13, 20))]}], "#
            + #""shared": [{"name": "Antigravity", "provider": "antigravity", "checkedAt": "2026-11-19T17:55:00Z", "#
            + #""state": "ok", "windows": [\#(gemini)]}, \#(spent("Codex", "codex")), \#(spent("Grok", "grok")), "#
            + #"\#(spent("OpenCode", "opencode"))]}"#
        let feed = try AgentFeed.decode(Data(json.utf8))
        let mine = feed.machines[1].accounts[0]
        let local = [
            AgentLocalAccount(name: "Claude", provider: "claude", reading: mine, folder: ""),
            AgentLocalAccount(name: "claude_team", provider: "claude",
                              reading: AgentAccount(name: "claude_team", provider: "claude", checkedAt: now, state: .signedOut),
                              folder: "/home/tester/.claude_team/"),
        ]
        return AgentBoard(home: home, machineName: "MBP", local: local, feed: .loaded(feed), now: now)
    }

    static func deck(_ board: AgentBoard) -> IslandPageDeck {
        var deck = IslandPageDeck()
        let page = AgentPage.page(board)
        deck.set(page, id: page.id)
        return deck
    }

    /// The island hanging from the screen's top edge, sized as `IslandPageHost` sizes it, below a notch or not.
    static func render(_ name: String, deck: IslandPageDeck, notch: Bool, frosted: Bool) -> CGSize {
        let pages = IslandPagesView(deck: deck, select: { _ in }, act: { _, _ in })
            .environment(\.metrics, InterfaceMetrics.standard)
            .environment(\.islandFrosted, frosted)
            .environment(\.paletteOnIsland, true)
            .environment(\.colorScheme, .dark)
        let fit = NSHostingView(rootView: pages).fittingSize
        let size = IslandPageDeck.outline(content: fit, rest: NotchTheme.Size.islandRest,
                                          notch: notch ? notchSize.width : nil, radius: Theme.Radius.panel,
                                          maxHeight: 2000)
        let top = notch ? notchSize.height : 0
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: Theme.Radius.panel,
                                           bottomTrailingRadius: Theme.Radius.panel, style: .continuous)
        let island = ZStack(alignment: .top) {
            shape.fill(frosted ? NotchTheme.Colors.islandGlassTint : NotchTheme.Colors.islandSurface)
            if frosted { shape.strokeBorder(NotchTheme.Colors.islandEdge, lineWidth: 1) }
            if notch { Rectangle().fill(Color.black).frame(width: notchSize.width, height: notchSize.height) }
            pages.frame(width: size.width, height: size.height).offset(y: top)
        }
        .frame(width: size.width, height: top + size.height)
        let canvas = CGSize(width: size.width + 2 * margin, height: top + size.height + margin)
        let view = island
            .frame(width: canvas.width, height: canvas.height, alignment: .top)
            .background(frosted ? Color.white : Color(white: 0.18))
            .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: canvas), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.frame = CGRect(origin: .zero, size: canvas)
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            preconditionFailure("\(name) has no bitmap")
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { preconditionFailure("\(name) PNG") }
        do {
            try png.write(to: folder.appendingPathComponent("\(name).png"))
        } catch {
            preconditionFailure("\(name): \(error)")
        }
        return size
    }
}
