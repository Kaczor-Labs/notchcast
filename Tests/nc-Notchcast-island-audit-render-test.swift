// notchcast-sources: Tinycast/Platform/Appearance.swift Tinycast/DesignSystem/Theme.swift
// notchcast-sources: Tinycast/DesignSystem/InterfaceMetrics.swift Tinycast/Features/Notchcast/NotchTheme.swift
// notchcast-sources: Tinycast/DesignSystem/KeyCapChip.swift Tinycast/DesignSystem/BarButton.swift
// notchcast-sources: Tinycast/DesignSystem/ModalActionButtonStyle.swift Tinycast/DesignSystem/SymbolImage.swift
// notchcast-sources: Tinycast/DesignSystem/Tooltip.swift Tinycast/DesignSystem/PopoverMenu.swift
// notchcast-sources: Tinycast/Windows/HUD/MessageHUDView.swift Tinycast/Windows/Dialog/DialogView.swift
// notchcast-sources: Tinycast/Windows/Dialog/DialogRequest.swift Tinycast/Windows/Dialog/DialogChip.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandHover.swift
// notchcast-sources: Tinycast/Features/Notchcast/IslandButtonFill.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandLevelDwell.swift
// notchcast-sources: Tinycast/Features/Island/Model/PillMenuRows.swift Tinycast/Features/Calendar/Model/*.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandNoticeArt.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandLevelArt.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandKeyline.swift Tinycast/Features/Island/Model/IslandLook.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandCanvas.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandExpansionArt.swift
// notchcast-sources: Tinycast/Platform/Images/IconCache.swift
// notchcast-sources: Tinycast/Features/Notchcast/NotchMenuInk.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandLiveState.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPaletteSurface.swift
// notchcast-sources: Tinycast/DesignSystem/FormTextInput.swift
// notchcast-sources: Tinycast/Features/Updates/UI/UpdatePill.swift Tinycast/Features/Updates/Model/AppVersion.swift
// notchcast-sources: Tinycast/Features/Updates/Model/ReleaseFeed.swift Tinycast/Features/Updates/Model/ReleaseChannel.swift
// notchcast-sources: Tinycast/Features/Updates/Model/ReleaseArchitecture.swift
// notchcast-sources: Tinycast/Features/Updates/Service/UpdateInstaller.swift
// notchcast-sources: Tinycast/Features/Updates/Service/UpdateFailure.swift
// notchcast-sources: Tinycast/DesignSystem/Scrolling/SelectionFollowing.swift
// notchcast-sources: Tinycast/DesignSystem/Scrolling/ScrollIntent.swift Tinycast/DesignSystem/Scrolling/SelectionReveal.swift
// notchcast-sources: Tinycast/Features/Updates/Service/Quarantine.swift Tinycast/DesignSystem/Scrolling/EdgeDissolve.swift
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

/// Audit only: renders the island's shared surfaces offscreen, in Dark on the island black, to PNGs
/// for a look audit against notchcast/docs/design-system.md. `NC_AUDIT_RENDERS` names the folder.
@MainActor
@main
struct NotchcastIslandAuditRenderTest {
    static let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["NC_AUDIT_RENDERS"]
        ?? NSTemporaryDirectory() + "nc-island-audit-renders")
    /// `NC_AUDIT_LOOK=frosted` renders Frosted on its glass tint over a white wallpaper.
    static let frosted = ProcessInfo.processInfo.environment["NC_AUDIT_LOOK"] == "frosted"
    /// `NC_AUDIT_SOLID=1` renders Frosted's no-blur fallback: each thickness's solid, and the menu solid.
    static let solid = ProcessInfo.processInfo.environment["NC_AUDIT_SOLID"] == "1"

    static func write(_ name: String, _ image: CGImage?) {
        guard let image else { preconditionFailure("\(name) did not render") }
        let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        guard let data else { preconditionFailure("\(name) has no PNG") }
        do {
            try data.write(to: folder.appendingPathComponent("\(name).png"))
        } catch {
            preconditionFailure("\(name): \(error)")
        }
    }

    /// Every SwiftUI surface sits on the island in its look, the way the island hosts it.
    static func render(_ name: String, glass: NotchTheme.GlassLayer = .bar, @ViewBuilder _ content: () -> some View) {
        let view = content()
            .padding(16)
            .background(ground(desk: false, glass: glass))
            .environment(\.islandFrosted, frosted)
            .environment(\.paletteOnIsland, true)
            .environment(\.colorScheme, .dark)
            .environment(PaletteState())
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        write(name, renderer.cgImage)
    }

    /// A field or scroll view is AppKit-backed and blank to `ImageRenderer`, so a window caches it.
    static func renderHosted(_ name: String, size: CGSize, desk: Bool = false, @ViewBuilder _ content: () -> some View) {
        let view = content()
            .padding(16)
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(ground(desk: desk))
            .environment(\.islandGlassBelow, solid)
            .environment(\.islandFrosted, frosted)
            .environment(\.paletteOnIsland, true)
            .environment(\.colorScheme, .dark)
            .environment(PaletteState())
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            preconditionFailure("\(name) has no bitmap")
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        write(name, bitmap.cgImage)
    }

    /// Black is the island black; Frosted the thickness's fill over white, or white alone under a floating menu.
    @ViewBuilder static func ground(desk: Bool, glass: NotchTheme.GlassLayer = .bar) -> some View {
        if !frosted {
            NotchTheme.Colors.islandSurface
        } else if desk {
            Color.white
        } else {
            glass.fill(solid: solid).background(Color.white)
        }
    }

    /// A report or a question as the island holds it: grown in that thickness from the top edge, with and
    /// without a 185 × 32 notch.
    static func renderHeld(_ name: String, _ glass: NotchTheme.GlassLayer, @ViewBuilder _ content: () -> some View) {
        let renderer = ImageRenderer(content: content().environment(\.islandFrosted, frosted)
            .environment(\.paletteOnIsland, true).environment(\.colorScheme, .dark))
        renderer.scale = 2
        guard let image = renderer.nsImage else { preconditionFailure("\(name) did not render") }
        let inset = NotchTheme.Spacing.islandInset
        let notchSize = CGSize(width: 185, height: 32)
        for notch in [false, true] {
            let top = notch ? notchSize.height : 0
            let island = CGSize(width: max(image.size.width + inset * 2, notchSize.width + 2 * Theme.Radius.panel),
                                height: top + image.size.height + inset * 2)
            let form = "\(notch ? "notch" : "nonotch")-\(frosted ? "frosted" : "black")\(solid ? "-solid" : "")"
            writeArt("\(name)-\(form)", size: CGSize(width: island.width + 64, height: island.height + 32)) { rect in
                (frosted ? NSColor.white : NSColor(white: 0.18, alpha: 1)).setFill()
                rect.fill()
                // Taller than the picture, so the top corners fall above the screen's edge.
                let shape = CGRect(x: 32, y: rect.maxY - island.height, width: island.width,
                                   height: island.height + Theme.Radius.panel)
                NSColor(frosted ? glass.fill(solid: solid) : NotchTheme.Colors.islandSurface).setFill()
                NSBezierPath(roundedRect: shape, xRadius: Theme.Radius.panel, yRadius: Theme.Radius.panel).fill()
                if notch {
                    NSColor.black.setFill()
                    CGRect(x: shape.midX - notchSize.width / 2, y: rect.maxY - notchSize.height,
                           width: notchSize.width, height: notchSize.height).fill()
                }
                image.draw(in: CGRect(x: shape.midX - image.size.width / 2, y: shape.minY + inset,
                                      width: image.size.width, height: image.size.height))
            }
        }
    }

    static func writeArt(_ name: String, size: CGSize, _ draw: @escaping (CGRect) -> Void) {
        let image = NSImage(size: size, flipped: false) { rect in
            draw(rect)
            return true
        }
        var proposed = CGRect(origin: .zero, size: size)
        write(name, image.cgImage(forProposedRect: &proposed, context: nil, hints: [.ctm: AffineTransform(scale: 2)]))
    }

    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        // ImageRenderer draws no Liquid Glass until a hosting view has laid glass out once.
        NSHostingView(rootView: Color.clear.frosted(in: Circle())).layoutSubtreeIfNeeded()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        render("01-keycaps") {
            HStack(spacing: 8) {
                KeyCapChip(text: "⌘", style: .outline)
                KeyCapChip(text: "K", style: .outline)
                KeyCapChip(text: "↵", style: .outline)
                Text("outline | filled (AIEmptyState)").foregroundStyle(.white).font(.caption)
                KeyCapChip(text: "↵")
            }
        }
        render("02-footer-capsule-today") {
            HStack(spacing: 8) {
                Color.clear.frame(width: 36, height: 36).frosted(in: Circle())
                HStack(spacing: 2) {
                    BarButton(action: {}) {
                        HStack(spacing: 6) {
                            Text("Open").font(.system(size: 13))
                            KeyCapChip(text: "↵", style: .outline)
                        }
                    }
                    BarButton(action: {}) {
                        HStack(spacing: 6) {
                            Text("Actions").foregroundStyle(Theme.Colors.textSecondary)
                            KeyCapChip(text: "⌘", style: .outline)
                            KeyCapChip(text: "K", style: .outline)
                        }
                    }
                }
                .padding(4)
                .frosted(in: Capsule())
            }
        }
        render("03-barbutton-states") {
            HStack(spacing: 8) {
                BarButton(action: {}) { Text("Rest") }
                BarButton(isSelected: true, action: {}) { Text("Selected (selection)") }
                Text("keyCapFill target:").foregroundStyle(.white).font(.caption)
                Text("Selected").padding(.horizontal, 10).frame(height: 28)
                    .background(NotchTheme.Colors.keyCapFill, in: Capsule())
            }
        }
        render("04-modal-buttons") {
            HStack(spacing: 8) {
                Button("Cancel") {}.buttonStyle(.modalAction(.cancel))
                Button("Standard") {}.buttonStyle(.modalAction(.standard))
                Button("Try Again") {}.buttonStyle(.modalAction(.primary))
                Button("Delete") {}.buttonStyle(.modalAction(.destructive))
            }
            .frame(width: 520)
        }
        render("05-message-hud", glass: .pane) {
            VStack(spacing: 12) {
                MessageHUDView(message: "Copied to Clipboard", accessory: .tone(.success))
                MessageHUDView(message: "Could not open the file", accessory: .tone(.danger))
                MessageHUDView(message: "Neutral report", accessory: .tone(.neutral))
                MessageHUDView(message: "Downloading…", accessory: .progress, onCancel: {})
            }
        }
        render("06-dialog-update-failed", glass: .sheet) {
            DialogView(
                request: DialogRequest(
                    title: "Update failed", message: "The download did not finish.",
                    symbol: IslandLiveState.failedSymbol, tone: .danger,
                    actions: [DialogAction(title: "OK", role: .cancel), DialogAction(title: "Try Again")],
                    defaultIndex: 1, cancelIndex: 0),
                width: 290, onChoose: { _ in })
        }
        render("07-dialog-neutral", glass: .sheet) {
            DialogView(
                request: DialogRequest(
                    title: "Quit Safari?", message: "Two windows are open.", symbol: "safari",
                    actions: [DialogAction(title: "Cancel", role: .cancel),
                              DialogAction(title: "Quit", role: .destructive)],
                    defaultIndex: 1, cancelIndex: 0),
                width: 420, onChoose: { _ in })
        }
        renderHeld("979-hud", .pane) {
            MessageHUDView(message: "Copied to Clipboard", accessory: .tone(.success))
        }
        renderHeld("979-dialog", .sheet) {
            DialogView(
                request: DialogRequest(
                    title: "Quit Safari?", message: "Two windows are open.", symbol: "safari",
                    actions: [DialogAction(title: "Cancel", role: .cancel),
                              DialogAction(title: "Quit", role: .destructive)],
                    defaultIndex: 1, cancelIndex: 0),
                width: 290, onChoose: { _ in })
        }
        render("08-dialog-chips", glass: .sheet) {
            HStack(spacing: 8) {
                DialogChip(title: "Rest", selected: false, onTap: {})
                DialogChip(title: "Selected", selected: true, onTap: {})
            }
        }
        renderHosted("09-popover-menu", size: CGSize(width: 360, height: 300), desk: true) {
            PopoverMenu(
                header: "Notchcast",
                items: [
                    PopoverMenuItem(title: "Open Settings", systemImage: "gearshape", shortcut: "⌘,") {},
                    PopoverMenuItem(title: "Check for Updates", systemImage: "arrow.down.circle") {},
                    PopoverMenuItem(title: "Quit Notchcast", systemImage: "power", isDestructive: true) {},
                ],
                selection: .constant(0), width: 320, visibleRows: 5, onActivate: { _ in },
                search: .init(placeholder: "Search…", placement: .top))
        }

        for (name, stage) in [
            ("15-update-pill-available", UpdateCoordinator.Stage.available(.sample)),
            ("16-update-pill-installing", .installing(.sample, .downloading(received: 40, expected: 100))),
            ("17-update-pill-opaque-step", .installing(.sample, .extracting)),
            ("18-update-pill-ready", .readyToRelaunch),
            ("19-update-pill-failed", .failed(.downloadFailed("The network dropped"))),
        ] {
            render(name) {
                UpdatePill().environment(UpdateCoordinator(stage: stage)).environment(\.paletteOnIsland, true)
            }
        }

        render("20-rows") {
            VStack(spacing: 2) {
                auditRow("Safari", subtitle: "Browser", trailing: "Application", fill: Theme.Colors.selection)
                    .selectionFrame(true)
                auditRow("Calculator", subtitle: nil, trailing: "Application", fill: Theme.Colors.rowHover)
                auditRow("Empty Trash", subtitle: "Finder", trailing: "Command", fill: .clear)
                Text("Search for apps and commands…").foregroundStyle(Theme.Colors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8).padding(.top, 8)
            }
            .frame(width: 480)
        }

        renderHosted("23-form-field", size: CGSize(width: 360, height: 80)) {
            FormTextInput(text: .constant(""), focused: .constant(false), placeholder: "Snippet Name", label: "Name",
                          moveFocus: { _ in })
                .environment(\.metrics, .standard)
        }
        for notch in [false, true] {
            renderHosted("26-launcher-footer-\(notch ? "notch" : "island")", size: CGSize(width: 600, height: 300)) {
                auditLauncherBottom(notch: notch)
            }
        }
        print("PASS rendered island audit surfaces to \(folder.path)")
    }
}

/// A launcher row's anatomy: title, secondary subtitle, tertiary kind label and a shortcut.
@MainActor
func auditRow(_ title: String, subtitle: String?, trailing: String, fill: Color) -> some View {
    HStack(spacing: 10) {
        RoundedRectangle(cornerRadius: 7).fill(Theme.Colors.success).frame(width: 28, height: 28)
        Text(title).foregroundStyle(Theme.Colors.textPrimary)
        if let subtitle { Text(subtitle).foregroundStyle(Theme.Colors.textSecondary) }
        KeyCapChip(text: "⌘", style: .outline)
        Spacer()
        Text(trailing).foregroundStyle(Theme.Colors.textTertiary)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .background(fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
}

/// The launcher's last rows scrolling under the footer, laid out as `RootPaletteView.bottomBar` (#898).
@MainActor
func auditLauncherBottom(notch: Bool) -> some View {
    ScrollView {
        VStack(spacing: 0) {
            ForEach(["Terminal", "Toggle Mute", "System Settings", "Generate Password", "TextEdit", "Notes", "Music", "Mail"],
                    id: \.self) { title in
                auditRow(title, subtitle: nil, trailing: "Application", fill: .clear)
            }
        }
        .padding(.horizontal, 8)
    }
    .edgeDissolve()
    .safeAreaInset(edge: .bottom, spacing: 0) {
        HStack(spacing: 0) {
            Color.clear.frame(width: 36, height: 36).floatingFrosted(in: Circle())
            Spacer()
            HStack(spacing: 2) {
                BarButton(action: {}) {
                    HStack(spacing: 6) {
                        Text("Open Application").font(.system(size: 13))
                        KeyCapChip(text: "↵", style: .outline)
                    }
                }
                BarButton(action: {}) {
                    HStack(spacing: 6) {
                        Text("Actions").foregroundStyle(Theme.Colors.textSecondary)
                        KeyCapChip(text: "⌘", style: .outline)
                        KeyCapChip(text: "K", style: .outline)
                    }
                }
            }
            .padding(4)
            .floatingFrosted(in: Capsule())
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }
    .overlay(alignment: .top) {
        if notch { UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10).fill(.black)
            .frame(width: 180, height: 16).offset(y: -16) }
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
    var body: some View { EmptyView() }
}

struct ClipboardEditField: View {
    let state: ClipboardEditState
    var body: some View { EmptyView() }
}
