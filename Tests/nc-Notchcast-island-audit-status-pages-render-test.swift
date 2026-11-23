// notchcast-hosted-only
// notchcast-kit: notchcast-island-audit
// notchcast-sources: Tests/Kit/IslandAuditMenus.swift Tests/ImageRendererBitmap.swift
// notchcast-sources: Tinycast/DesignSystem/KeyCapChip.swift Tinycast/DesignSystem/BarButton.swift
// notchcast-sources: Tinycast/DesignSystem/ModalActionButtonStyle.swift Tinycast/DesignSystem/SymbolImage.swift
// notchcast-sources: Tinycast/DesignSystem/Tooltip.swift Tinycast/DesignSystem/PopoverMenu.swift
// notchcast-sources: Tinycast/Windows/HUD/MessageHUDView.swift Tinycast/Windows/Dialog/DialogView.swift
// notchcast-sources: Tinycast/Windows/Dialog/DialogRequest.swift
// notchcast-sources: Tinycast/Features/Notchcast/IslandButtonFill.swift
// notchcast-sources: Tinycast/Features/Notchcast/NotchMenuInk.swift
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

@MainActor
@main
struct IslandAuditStatusPagesRenderTest {
    static func main() {
        IslandAuditRendering.prepare()
        IslandAuditRendering.renderStatusAndPages()
        print("PASS rendered island status pages audit surfaces to \(IslandAuditRendering.folder.path)")
    }
}

// PopoverMenu reads it; the real one drags in the whole island, and a release build is never stock.
@MainActor
enum IslandVerification {
    static let stock = false
}

extension IslandAuditRendering {
    static func renderStatusAndPages() {
        renderMenuKeylines()

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
                    symbol: IslandLiveState.failedSymbol, tone: .danger,
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
        renderHosted("09-popover-menu", size: CGSize(width: 360, height: 300), desk: frosted) {
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
            let form = notch ? "notch" : "island"
            renderArt("13-status-\(form)", IslandStatusArt(
                [IslandStatus(id: "u", symbol: "arrow.clockwise.circle", text: nil, label: "Update ready")],
                notch: notch, frosted: frosted))
            for tone in IslandTone.allCases { renderArt("13t-status-\(tone)-\(form)", IslandStatusArt([IslandStatus(id: "cpu",
                symbol: "cpu", text: "Hot", label: "CPU running hot", tone: tone)], notch: notch, frosted: frosted)) }
            renderArt("14-level-\(form)", IslandLevelArt(
                IslandLevel(source: "volume", symbol: "speaker.wave.2.fill", label: "Volume", value: 0.6),
                notch: notch, frosted: frosted))
            renderArt("14b-level-muted-\(form)", IslandLevelArt(
                IslandLevel(source: "volume", symbol: "speaker.slash.fill", label: "Volume", value: 0),
                notch: notch, frosted: frosted))
            renderArt("14c-level-brightness-\(form)", IslandLevelArt(
                IslandLevel(source: "brightness", symbol: "sun.max.fill", label: "Brightness", value: 1,
                            range: -0.25...1), notch: notch, frosted: frosted))
            renderArt("14d-level-extra-dimming-\(form)", IslandLevelArt(
                IslandLevel(source: "brightness", symbol: "sun.min.fill", label: "Brightness", value: -0.125,
                            range: -0.25...1), notch: notch, frosted: frosted))
            renderArt("14f-level-darkest-\(form)", IslandLevelArt(
                IslandLevel(source: "brightness", symbol: "sun.min.fill", label: "Brightness", value: -0.25,
                            range: -0.25...1), notch: notch, frosted: frosted))
            renderArt("14g-level-system-minimum-\(form)", IslandLevelArt(
                IslandLevel(source: "brightness", symbol: "sun.max.fill", label: "Brightness", value: 0,
                            range: -0.25...1), notch: notch, frosted: frosted))
            renderArt("14h-level-brightness-half-\(form)", IslandLevelArt(
                IslandLevel(source: "brightness", symbol: "sun.max.fill", label: "Brightness", value: 0.5,
                            range: -0.25...1), notch: notch, frosted: frosted))
        }
        renderArt("14e-level-notch-low", IslandLevelArt(
            IslandLevel(source: "volume", symbol: "speaker.wave.1.fill", label: "Volume", value: 0.31),
            notch: true, frosted: frosted))
        let meeting = MeetingEvent(id: "m", title: "Standup", start: Date(timeIntervalSince1970: 600),
            end: Date(timeIntervalSince1970: 2400), isAllDay: false, isDeclined: false, calendarID: "c",
            calendarName: "Work", calendarColor: nil, calendarItemID: "i", link: nil)
        let expansion = IslandExpansionArt(IslandGlance(meeting, now: Date(timeIntervalSince1970: 0),
            locale: Locale(identifier: "en_US")), frosted: frosted)
        let room = CGRect(x: 16, y: 16, width: expansion.size.width, height: expansion.size.height)
        writeArt("25-meeting-expansion-notch", size: CGSize(width: room.width + 32, height: room.height + 32)) { rect in
            paintPill(rect, pill: NSBezierPath(roundedRect: room, xRadius: 16, yRadius: 16))
            expansion.draw(in: room)
        }
        renderMeetingAndSong(meeting)
        renderBand("22-level-band", IslandLevelArt(
            IslandLevel(source: "volume", symbol: "speaker.wave.2.fill", label: "Volume", value: 0.6),
            notch: false, frosted: frosted))
        for notch in [false, true] {
            renderHosted("26-launcher-footer-\(notch ? "notch" : "island")", size: CGSize(width: 600, height: 300)) {
                auditLauncherBottom(notch: notch)
            }
        }
    }

    /// Every SwiftUI surface sits on the island in its look, the way the island hosts it.
    static func render(_ name: String, @ViewBuilder _ content: () -> some View) {
        let view = content()
            .padding(16)
            .background(ground(desk: false))
            .environment(\.islandFrosted, frosted)
            .environment(\.paletteOnIsland, true)
            .environment(\.colorScheme, .dark)
            .environment(PaletteState())
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        write(name, renderer.bitmap)
    }

    /// The level band in the report slot: on Frosted it must leave the glass under it unpainted.
    static func renderBand(_ name: String, _ art: IslandLevelArt) {
        let band = IslandLevelBand(frame: CGRect(origin: .zero, size: art.bandSize))
        band.art = art
        let box = CGRect(x: 16, y: 16, width: art.bandSize.width, height: art.bandSize.height)
        writeArt(name, size: CGSize(width: box.width + 32, height: box.height + 32)) { rect in
            paintPill(rect, pill: NSBezierPath(rect: box))
            let image = NSImage(size: box.size, flipped: false) { _ in
                band.draw(band.bounds)
                return true
            }
            image.draw(in: box)
        }
    }

    private static func renderMeetingAndSong(_ meeting: MeetingEvent) {
        let glance = IslandGlance(meeting, now: Date(timeIntervalSince1970: 0), locale: Locale(identifier: "en_US"))
        let ready = IslandStatus(id: "update", symbol: "arrow.clockwise.circle", text: nil, label: "Update ready")
        let cover = NSImage(size: CGSize(width: 64, height: 64), flipped: false) { rect in
            NSGradient(colors: [.systemOrange, .systemPink, .systemPurple])?.draw(in: rect, angle: 45)
            return true
        }
        let art = cover.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))?.representation(using: .png, properties: [:])
        let song = IslandNowPlaying(title: "Paper Lanterns", artist: "Juno Vale", artwork: art, time: nil, isPlaying: true,
                                    id: "a")
        var long = song
        long.title = "Everything Everywhere at Once (Extended Midnight Version)"
        long.artist = "Juno Vale, The Paper Lanterns Orchestra"
        let look = frosted ? "frosted" : "black"
        for notch in [false, true] {
            let form = notch ? "notch" : "nonotch"
            let meetingArt = GlanceArt(glance, notch: notch, frosted: frosted)
            compact("884-04-meeting-\(form)-\(look)", meetingArt, notch: notch)
            let expansion = IslandExpansionArt(glance, frosted: frosted)
            island("884-05-meeting-hover-\(form)-\(look)",
                   width: max(expansion.size.width, compactWidth(meetingArt, notch: notch)), body: expansion.size.height,
                   notch: notch, radius: Theme.Radius.panel) { expansion.draw(in: $0) }
            compact("884-06-status-\(form)-\(look)", IslandStatusArt([ready], notch: notch, frosted: frosted),
                    notch: notch)
            func songGlance(_ step: String, _ base: IslandNowPlaying,
                            _ change: (inout IslandNowPlaying) -> Void = { _ in }) {
                var shown = base
                change(&shown)
                let cover = IslandCover.image(shown.artwork, side: IslandSongArt.cell, scale: 2, frosted: frosted)
                compact("850-\(step)-\(form)-\(look)", IslandSongArt(shown, notch: notch, frosted: frosted, still: true,
                                                                     cover: cover), notch: notch)
            }
            island("850-00-no-song-\(form)-\(look)", width: notch ? 185 : NotchTheme.Size.islandRest.width,
                   body: notch ? 0 : NotchTheme.Size.islandRest.height, notch: notch, radius: notch ? 10 : 12) { _ in }
            songGlance("01-song-playing", song)
            songGlance("02-song-paused", song) { $0.isPlaying = false }
            songGlance("03-song-cover-loading", song) { $0.artwork = nil }
            for overflow in IslandSongOverflow.allCases where !notch {
                songGlance("04-song-long-\(overflow.rawValue)", long) { $0.overflow = overflow }
            }
            for (name, playing) in [("850-05-song-change", song), ("850-06-song-change-long", long)] where notch {
                let cover = IslandCover.image(playing.artwork, side: IslandSongArt.cell, scale: 2, frosted: frosted)
                let change = IslandExpansionArt(playing, cover: cover, frosted: frosted)
                let width = compactWidth(IslandSongArt(playing, notch: true, frosted: frosted, still: true, cover: cover),
                                         notch: true)
                island("\(name)-\(form)-\(look)", width: max(change.size.width, width), body: change.size.height,
                       notch: true, radius: Theme.Radius.panel) { change.draw(in: $0) }
            }
        }
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
    var onSubmit: () -> Void = {}
    var body: some View { EmptyView() }
}

struct ClipboardEditField: View {
    let state: ClipboardEditState
    var body: some View { EmptyView() }
}
class SecretFieldState {}; struct DialogSecretField: View { let state: SecretFieldState; var body: some View { EmptyView() } }
