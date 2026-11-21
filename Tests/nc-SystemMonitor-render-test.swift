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
// notchcast-sources: Tinycast/Features/Island/Service/IslandNoticeArt.swift
// notchcast-sources: Tinycast/Features/Notchcast/SystemMonitor/Model/*.swift
// notchcast-sources: Tests/nc-SystemMonitor-fixtures.swift
// notchcast-sources: Tinycast/DesignSystem/ModalActionButtonStyle.swift Tinycast/DesignSystem/PopoverMenu.swift
// notchcast-sources: Tinycast/Windows/HUD/MessageHUDView.swift Tinycast/Windows/Dialog/DialogView.swift
// notchcast-sources: Tinycast/Windows/Dialog/DialogRequest.swift Tinycast/Features/Island/Model/IslandHover.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandLevelDwell.swift
// notchcast-sources: Tinycast/Features/Island/Model/PillMenuRows.swift Tinycast/Features/Calendar/Model/*.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandLevelArt.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandKeyline.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandCanvas.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandExpansionArt.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandSongArt.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandLiveState.swift Tinycast/DesignSystem/FormTextInput.swift
// notchcast-sources: Tinycast/Features/Updates/UI/UpdatePill.swift Tinycast/Features/Updates/Model/AppVersion.swift
// notchcast-sources: Tinycast/Features/Updates/Model/ReleaseFeed.swift
// notchcast-sources: Tinycast/Features/Updates/Model/ReleaseChannel.swift
// notchcast-sources: Tinycast/Features/Updates/Model/ReleaseArchitecture.swift
// notchcast-sources: Tinycast/Features/Updates/Service/UpdateInstaller.swift
// notchcast-sources: Tinycast/Features/Updates/Service/UpdateFailure.swift
// notchcast-sources: Tinycast/DesignSystem/Scrolling/SelectionFollowing.swift
// notchcast-sources: Tinycast/DesignSystem/Scrolling/ScrollIntent.swift
// notchcast-sources: Tinycast/DesignSystem/Scrolling/SelectionReveal.swift
// notchcast-sources: Tinycast/Features/Updates/Service/Quarantine.swift
// notchcast-sources: Tinycast/DesignSystem/Scrolling/EdgeDissolve.swift
// notchcast-sources: Tinycast/Features/Updates/Service/BundleSignature.swift
// notchcast-sources: Tinycast/Features/Updates/Service/ToolRunner.swift
// notchcast-sources: Tinycast/Features/Updates/Service/UpdateDownloader.swift
// notchcast-sources: Tinycast/Features/Updates/Service/UpdateSignature.swift
import AppKit
import SwiftUI

// PopoverMenu reads it; the real one drags in the whole island, and a release build is never stock.
@MainActor
enum IslandVerification {
    static let stock = false
}

/// #977's acceptance set: the System page and Home, normal and hot, and the closed island's hot glyph,
/// in both forms on Black and Frosted. `NC_AUDIT_RENDERS` names the folder, else the audit harness's own.
@MainActor
@main
struct SystemMonitorRenderTest {
    typealias Fix = MonitorFixtures

    static let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["NC_AUDIT_RENDERS"]
        ?? NSTemporaryDirectory() + "nc-island-audit-renders")
    static let notchSize = CGSize(width: 185, height: 32)
    static let margin: CGFloat = 32

    static func main() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let normal = Fix.board()
        let hot = Fix.board(cpu: 0.96, pressure: .critical, freePercent: 3, hotFor: 12)
        let player = IslandPlayerPage.page(IslandNowPlaying(
            title: "Paper Lanterns", artist: "Juno Vale", artwork: nil,
            time: IslandMediaTime(elapsed: 72, duration: 214, rate: 0, sampledAt: Date(timeIntervalSince1970: 0)),
            isPlaying: true))
        let decks = [
            ("system-normal", deck([MonitorPage.page(normal, locale: Fix.locale)])),
            ("system-hot", deck([MonitorPage.page(hot, locale: Fix.locale)])),
            ("system-measuring", deck([MonitorPage.page(MonitorBoard(), locale: Fix.locale)])),
            ("home-normal", deck([player, MonitorPage.page(normal, locale: Fix.locale)])),
            ("home-hot", deck([player, MonitorPage.page(hot, locale: Fix.locale)])),
        ]
        guard let status = MonitorPage.status(hot.heat) else { preconditionFailure("a hot board has a status") }
        var sizes: [String: CGSize] = [:]
        for frosted in [false, true] {
            for notch in [false, true] {
                let suffix = "\(notch ? "notch" : "island")-\(frosted ? "frosted" : "black")"
                for (name, deck) in decks {
                    sizes[name] = render("977-\(name)-\(suffix)", deck: deck, notch: notch, frosted: frosted)
                }
                closed("977-closed-hot-\(suffix)", IslandStatusArt([status], notch: notch, frosted: frosted),
                       notch: notch, frosted: frosted)
            }
        }
        precondition(sizes["home-normal"]!.height < sizes["system-normal"]!.height, "Home is one line per page")
        print("PASS rendered the System page to \(folder.path)")
    }

    static func deck(_ pages: [IslandPage]) -> IslandPageDeck {
        var deck = IslandPageDeck()
        for page in pages { deck.set(page, id: page.id) }
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

    /// The resting island with the status glyph, as the audit harness draws a compact pill, below a notch or not.
    static func closed(_ name: String, _ art: IslandStatusArt, notch: Bool, frosted: Bool) {
        let inner = notch ? Theme.Spacing.md : 0
        let width = max((notch ? notchSize.width : 0) + 2 * (Theme.Spacing.lg + inner) + art.layout.leading
                        + art.layout.trailing, notch ? notchSize.width : NotchTheme.Size.islandRest.width)
        let body = notch ? 0 : NotchTheme.Size.islandRest.height
        let top = notch ? notchSize.height : 0
        let radius: CGFloat = notch ? 10 : 12
        let size = CGSize(width: width + 2 * margin, height: top + body + margin)
        let image = NSImage(size: size, flipped: false) { rect in
            (frosted ? NSColor.white : NSColor(white: 0.18, alpha: 1)).setFill()
            rect.fill()
            let shape = CGRect(x: margin, y: rect.maxY - top - body, width: width, height: top + body)
            let path = notch ? NSBezierPath(roundedRect: shape, xRadius: radius, yRadius: radius)
                : NSBezierPath(roundedRect: shape, xRadius: body / 2, yRadius: body / 2)
            NSColor(frosted ? NotchTheme.Colors.islandGlassTint : NotchTheme.Colors.islandSurface).setFill()
            path.fill()
            if notch {
                NSColor.black.setFill()
                CGRect(x: shape.minX + Theme.Spacing.lg + Theme.Spacing.md + art.layout.leading,
                       y: rect.maxY - notchSize.height, width: notchSize.width, height: notchSize.height).fill()
            }
            art.draw(in: notch ? CGRect(x: shape.minX, y: shape.minY, width: shape.width, height: top) : shape)
            return true
        }
        var proposed = CGRect(origin: .zero, size: size)
        guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil,
                                          hints: [.ctm: AffineTransform(scale: 2)]),
              let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
            preconditionFailure("\(name) did not render")
        }
        do {
            try png.write(to: folder.appendingPathComponent("\(name).png"))
        } catch {
            preconditionFailure("\(name): \(error)")
        }
    }
}

/// Stand-in for the coordinator `UpdatePill` reads, so the pill renders without `AppCore`.
@MainActor
@Observable
final class UpdateCoordinator {
    enum Stage: Equatable {
        case idle
        case checking
        case available(AvailableRelease)
        case installing(AvailableRelease, UpdateInstaller.Phase)
        case readyToRelaunch
        case failed(UpdateFailure)
    }

    let stage: Stage
    init(stage: Stage) { self.stage = stage }
    func install() {}
    func relaunch() {}
    func showFailure() {}
    func dismiss() {}
}

extension AvailableRelease {
    static let sample = AvailableRelease(
        version: AppVersion("1.2.3")!, tag: "v1.2.3", assetURL: URL(string: "https://example.com/a.zip")!,
        assetSize: 100, signatureURL: nil, publishedAt: nil)
}

/// Stand-ins for the palette state `PopoverMenu` reads, so the menu renders without `AppCore`.
@MainActor
@Observable
final class PaletteState {
    var menuQuery = ""
    var menuPresentationToken = UUID()
    var hoverHighlightArmed = false
}

struct PasteTarget {
    var iconPath: String?
}

/// The dialog's accessories are out of this audit's scope; empty stand-ins keep `DialogView` whole.
final class VolumeState {}
final class SnippetArgumentsState {}
final class ClipboardEditState {}

struct VolumeSlider: View {
    let state: VolumeState
    var body: some View { EmptyView() }
}

struct SnippetArgumentFields: View {
    let state: SnippetArgumentsState
    var onSubmit: () -> Void = {}
    var body: some View { EmptyView() }
}

struct ClipboardEditField: View {
    let state: ClipboardEditState
    var body: some View { EmptyView() }
}
