// notchcast-sources: Tinycast/Platform/Appearance.swift Tinycast/DesignSystem/Theme.swift
// notchcast-sources: Tinycast/DesignSystem/InterfaceMetrics.swift Tinycast/Features/Notchcast/NotchTheme.swift
// notchcast-sources: Tinycast/DesignSystem/KeyCapChip.swift Tinycast/DesignSystem/BarButton.swift
// notchcast-sources: Tinycast/DesignSystem/ModalActionButtonStyle.swift Tinycast/DesignSystem/SymbolImage.swift
// notchcast-sources: Tinycast/DesignSystem/Tooltip.swift Tinycast/DesignSystem/PopoverMenu.swift
// notchcast-sources: Tinycast/Windows/HUD/MessageHUDView.swift Tinycast/Windows/Dialog/DialogView.swift
// notchcast-sources: Tinycast/Windows/Dialog/DialogRequest.swift Tinycast/Windows/Dialog/DialogChip.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandLevelDwell.swift
// notchcast-sources: Tinycast/Features/Island/Model/PillMenuRows.swift Tinycast/Features/Calendar/Model/*.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandNoticeArt.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandLevelArt.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandCanvas.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandExpansionArt.swift
// notchcast-sources: Tinycast/Platform/Images/IconCache.swift
// notchcast-sources: Tinycast/Features/Notchcast/NotchMenuInk.swift
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

    /// Every SwiftUI surface sits on the island black, the way the island hosts it.
    static func render(_ name: String, @ViewBuilder _ content: () -> some View) {
        let view = content()
            .padding(16)
            .background(NotchTheme.Colors.islandSurface)
            .environment(\.colorScheme, .dark)
            .environment(PaletteState())
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        write(name, renderer.cgImage)
    }

    /// A field or scroll view is AppKit-backed and blank to `ImageRenderer`, so a window caches it.
    static func renderHosted(_ name: String, size: CGSize, @ViewBuilder _ content: () -> some View) {
        let view = content()
            .padding(16)
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(NotchTheme.Colors.islandSurface)
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

    /// Engine art draws in AppKit into the pill's outline, so it renders the way the canvas does.
    static func renderArt(_ name: String, _ art: some PillArt) {
        let width = art.layout.leading + art.layout.trailing + 2 * Theme.Spacing.lg
        let size = CGSize(width: max(width, NotchTheme.Size.islandRest.width), height: 36)
        let image = NSImage(size: CGSize(width: size.width + 32, height: size.height + 32), flipped: false) { rect in
            NSColor(white: 0.18, alpha: 1).setFill()
            rect.fill()
            let pill = CGRect(x: 16, y: 16, width: size.width, height: size.height)
            NSColor(NotchTheme.Colors.islandSurface).setFill()
            NSBezierPath(roundedRect: pill, xRadius: size.height / 2, yRadius: size.height / 2).fill()
            art.draw(in: pill)
            return true
        }
        var proposed = CGRect(origin: .zero, size: image.size)
        let scaled = NSImage(size: image.size)
        scaled.addRepresentations(image.representations)
        write(name, image.cgImage(forProposedRect: &proposed, context: nil,
                                  hints: [.ctm: AffineTransform(scale: 2)]))
    }

    static func main() {
        _ = NSApplication.shared
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
        render("05-message-hud") {
            VStack(spacing: 12) {
                MessageHUDView(message: "Copied to Clipboard", accessory: .tone(.success))
                MessageHUDView(message: "Could not open the file", accessory: .tone(.danger))
                MessageHUDView(message: "Neutral report", accessory: .tone(.neutral))
                MessageHUDView(message: "Downloading…", accessory: .progress, onCancel: {})
            }
        }
        render("06-dialog-update-failed") {
            DialogView(
                request: DialogRequest(
                    title: "Update failed", message: "The download did not finish.",
                    symbol: "arrow.down.circle", tone: .danger,
                    actions: [DialogAction(title: "OK", role: .cancel), DialogAction(title: "Try Again")],
                    defaultIndex: 1, cancelIndex: 0),
                width: 290, onChoose: { _ in })
        }
        render("07-dialog-neutral") {
            DialogView(
                request: DialogRequest(
                    title: "Quit Safari?", message: "Two windows are open.", symbol: "safari",
                    actions: [DialogAction(title: "Cancel", role: .cancel),
                              DialogAction(title: "Quit", role: .destructive)],
                    defaultIndex: 1, cancelIndex: 0),
                width: 420, onChoose: { _ in })
        }
        render("08-dialog-chips") {
            HStack(spacing: 8) {
                DialogChip(title: "Rest", selected: false, onTap: {})
                DialogChip(title: "Selected", selected: true, onTap: {})
            }
        }
        renderHosted("09-popover-menu", size: CGSize(width: 360, height: 300)) {
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

        let notch = false
        renderArt("10-notice-glyph", IslandNoticeArt(
            IslandNotice(id: "a", symbol: "doc.on.clipboard", text: "Copied"), notch: notch))
        renderArt("11-notice-installing", IslandNoticeArt(
            IslandNotice(id: "b", symbol: "arrow.down.circle", text: "Installing",
                         progress: IslandProgress(fraction: 0.4, headline: false)), notch: notch))
        renderArt("12-notice-failed", IslandNoticeArt(
            IslandNotice(id: "c", symbol: "exclamationmark.arrow.circlepath", text: "Update failed",
                         isFailure: true, seconds: 4), notch: notch))
        renderArt("13-status", IslandStatusArt(
            [IslandStatus(id: "u", symbol: "arrow.clockwise.circle", text: nil, label: "Update ready")], notch: notch))
        renderArt("14-level", IslandLevelArt(
            IslandLevel(source: "volume", symbol: "speaker.wave.2.fill", label: "Volume", value: 0.6), notch: notch))
        print("PASS rendered island audit surfaces to \(folder.path)")
    }
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
