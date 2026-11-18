// notchcast-sources: Tinycast/Features/Notchcast/Spotify/SpotifyAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/Spotify/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Spotify/Service/SpotifyModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Spotify/Service/SpotifyModule+Commands.swift
// notchcast-sources: Tinycast/Features/Notchcast/Spotify/Service/SpotifyModule+Web.swift
// notchcast-sources: Tinycast/Features/Notchcast/Spotify/Service/SpotifySystem.swift
// notchcast-sources: Tinycast/Features/Notchcast/Spotify/Service/SpotifyWeb.swift
// notchcast-sources: Tinycast/Features/Notchcast/Spotify/Service/SpotifyIsland.swift
// notchcast-sources: Tinycast/Features/Notchcast/Spotify/UI/SpotifyPlayerView.swift
// notchcast-sources: Tinycast/Features/Notchcast/Spotify/UI/SpotifyUpNextView.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastContext.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastTranscription.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastTap.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastTapHub.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastTapRouter.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastTapThread.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandMedia.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandLook.swift
// notchcast-sources: Tinycast/Features/Island/Model/PillMenuRows.swift Tinycast/Features/Calendar/Model/*.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandMediaPresenting.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandMediaArt.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandExpansionArt.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPaletteSurface.swift
// notchcast-sources: Tinycast/Platform/Appearance.swift Tinycast/DesignSystem/Theme.swift
// notchcast-sources: Tinycast/DesignSystem/InterfaceMetrics.swift Tinycast/Features/Notchcast/NotchTheme.swift
// notchcast-sources: Tinycast/Features/Launcher/UI/SectionHeader.swift Tinycast/DesignSystem/Tooltip.swift
// notchcast-sources: Tinycast/DesignSystem/IconTint.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift

// notchcast-sources: Tinycast/DesignSystem/KeyCapChip.swift
import SwiftUI

// The settings views are left out; the player and Up Next are the shipped ones.
struct SpotifySettingsView: View {
    init(context: NotchcastContext) {}
    var body: some View { EmptyView() }
}

struct SpotifyIslandSettingsRow: View {
    init(context: NotchcastContext) {}
    var body: some View { EmptyView() }
}

// GlanceArt's glyph helper lives in IslandCanvas, which drags in the whole engine.
enum GlanceArt {
    static func glyph(_ name: String, tone: NSColor) -> NSImage? { nil }
}

@MainActor
protocol PillArt {
    var layout: IslandGlanceLayout { get }
    func draw(in pill: CGRect)
}

extension SpotifySystem {
    static var live: SpotifySystem { Render.system }
}

/// Renders every PR B state offscreen to `NC_AUDIT_RENDERS`, in the look `NC_AUDIT_LOOK` names.
@MainActor
@main
struct Render {
    static let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["NC_AUDIT_RENDERS"]
        ?? NSTemporaryDirectory() + "nc-spotify-island-renders")
    static let frosted = ProcessInfo.processInfo.environment["NC_AUDIT_LOOK"] == "frosted"
    static let look = frosted ? "frosted" : "black"
    static let notch = CGSize(width: 185, height: 32)

    /// A made-up cover in warm tones, standing in for Spotify's art; nothing is fetched.
    nonisolated static let cover: Data = {
        let image = NSImage(size: CGSize(width: 64, height: 64), flipped: false) { rect in
            NSGradient(colors: [NSColor(srgbRed: 0.85, green: 0.45, blue: 0.3, alpha: 1),
                                NSColor(srgbRed: 0.6, green: 0.25, blue: 0.2, alpha: 1)])?.draw(in: rect, angle: -60)
            NSColor(white: 1, alpha: 0.35).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 18, dy: 18).offsetBy(dx: 4, dy: -4)).fill()
            return true
        }
        let tiff = image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))
        return tiff?.representation(using: .png, properties: [:]) ?? Data()
    }()

    static var system: SpotifySystem {
        SpotifySystem(
            now: { Date(timeIntervalSince1970: 1_800_000_000) }, soloistKey: { nil }, setSoloistKey: { _ in },
            tokens: { nil }, setTokens: { _ in }, installedBuild: { nil },
            install: { throw SoloistInstallError.install },
            launch: { _, _, _ in throw SoloistLaunchError.notInstalled },
            connect: { _, _, _ in SoloistLink(send: { _ in }, close: {}) },
            wake: { _, _ in {} },
            nowPlaying: SpotifyNowPlayingSink(update: { _, _ in }, commands: { _ in }),
            web: SpotifyWebTransport(send: { _ in .init(status: 200, body: Render.cover, retryAfter: nil) },
                                     awaitRedirect: { _, _ in [:] }),
            openURL: { _ in })
    }

    static func write(_ name: String, _ image: CGImage?) {
        guard let image, let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { preconditionFailure("\(name) did not render") }
        do { try data.write(to: folder.appendingPathComponent("\(name).png")) } catch { preconditionFailure("\(error)") }
    }

    static func ground(_ rect: CGRect) {
        (frosted ? NSColor.white : NSColor(white: 0.18, alpha: 1)).setFill()
        rect.fill()
    }

    static func islandFill() -> NSColor {
        NSColor(frosted ? NotchTheme.Colors.islandGlassTint : NotchTheme.Colors.islandSurface)
    }

    /// The island hanging from the top edge: a notch with wings, or the 24 pt pill; `body` grows below.
    static func island(_ name: String, width: CGFloat, body: CGFloat, notched: Bool, radius: CGFloat,
                       _ draw: @escaping (CGRect) -> Void) {
        let top = notched ? notch.height : 0
        let size = CGSize(width: width + 64, height: top + body + 32)
        let image = NSImage(size: size, flipped: false) { rect in
            ground(rect)
            let shape = CGRect(x: 32, y: rect.maxY - top - body, width: width, height: top + body)
            islandFill().setFill()
            if !notched, body <= NotchTheme.Size.islandRest.height {
                NSBezierPath(roundedRect: shape, xRadius: body / 2, yRadius: body / 2).fill()
            } else {
                let path = NSBezierPath()
                path.move(to: CGPoint(x: shape.minX, y: rect.maxY))
                path.line(to: CGPoint(x: shape.minX, y: shape.minY + radius))
                path.appendArc(withCenter: CGPoint(x: shape.minX + radius, y: shape.minY + radius), radius: radius,
                               startAngle: 180, endAngle: 270)
                path.line(to: CGPoint(x: shape.maxX - radius, y: shape.minY))
                path.appendArc(withCenter: CGPoint(x: shape.maxX - radius, y: shape.minY + radius), radius: radius,
                               startAngle: 270, endAngle: 360)
                path.line(to: CGPoint(x: shape.maxX, y: rect.maxY))
                path.close()
                path.fill()
            }
            if notched {
                NSColor.black.setFill()
                CGRect(x: shape.midX - notch.width / 2, y: rect.maxY - notch.height, width: notch.width,
                       height: notch.height).fill()
            }
            draw(notched && body == 0 ? CGRect(x: shape.minX, y: shape.minY, width: shape.width, height: top)
                 : CGRect(x: shape.minX, y: shape.minY, width: shape.width, height: body))
            return true
        }
        var proposed = CGRect(origin: .zero, size: size)
        write(name, image.cgImage(forProposedRect: &proposed, context: nil, hints: [.ctm: AffineTransform(scale: 2)]))
    }

    /// As the engine sizes compact slots: inner padding beside a notch, `lg` at each end.
    static func compact(_ name: String, _ art: MediaGlanceArt, notched: Bool) {
        let inner = notched ? Theme.Spacing.md : 0
        let width = (notched ? notch.width : 0) + 2 * (Theme.Spacing.lg + inner) + art.layout.leading
            + art.layout.trailing
        island(name, width: width, body: notched ? 0 : NotchTheme.Size.islandRest.height, notched: notched,
               radius: notched ? 10 : 12) { art.draw(in: $0) }
    }

    /// The page as the island hosts it: below the notch, the island's 16 pt inset all round.
    static func page(_ name: String, notched: Bool, module: SpotifyModule, covers: SpotifyCovers) {
        let inset = NotchTheme.Spacing.islandInset
        let size = SpotifyPlayerView.pageSize
        let top = notched ? notch.height : 0
        let canvas = CGSize(width: size.width + inset * 2 + 64, height: top + size.height + inset * 2 + 32)
        let view = ZStack(alignment: .top) {
            Color(nsColor: frosted ? .white : NSColor(white: 0.18, alpha: 1))
            UnevenRoundedRectangle(bottomLeadingRadius: Theme.Radius.panel, bottomTrailingRadius: Theme.Radius.panel)
                .fill(frosted ? NotchTheme.Colors.islandGlassTint : NotchTheme.Colors.islandSurface)
                .frame(width: size.width + inset * 2, height: top + size.height + inset * 2)
            if notched { Color.black.frame(width: notch.width, height: notch.height) }
            SpotifyPlayerView(module: module)
                .frame(width: size.width, height: size.height)
                .padding(.top, top + inset)
        }
        .frame(width: canvas.width, height: canvas.height, alignment: .top)
        .environment(covers)
        .environment(\.islandFrosted, frosted)
        .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: canvas), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.frame = CGRect(origin: .zero, size: canvas)
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        }
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { preconditionFailure(name) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        write(name, bitmap.cgImage)
    }

    static func playback(title: String, artists: [String], playing: Bool, at positionMs: Int) -> SpotifyPlayback {
        var playback = SpotifyPlayback()
        playback.status = playing ? .playing : .paused
        playback.volume = 62
        playback.position = SpotifyPosition(positionMs: positionMs, timestamp: Date(), speed: 0)
        let art = URL(string: "https://i.scdn.co/cover")
        playback.track = SpotifyTrack(id: "spotify:track:\(title)", title: title, artists: artists, album: nil,
                                      artworkURL: art, thumbnailURL: art, durationMs: 228_000)
        playback.upNext = ["Glass Harbour", "Low Tide Radio", "Northern Static", "Saltwater Hymn"].map {
            let track = SpotifyTrack(id: "spotify:track:\($0)", title: $0, artists: ["Juno Vale"], album: nil,
                                     artworkURL: art, thumbnailURL: art, durationMs: 200_000)
            return SpotifyQueueEntry(id: $0, track: track, source: .context)
        }
        return playback
    }

    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let suite = "nc-spotify-island-render.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let hub = NotchcastTapHub(syntheticTag: 0, isTrusted: { false }) { _ in preconditionFailure("no tap") }
        final class Silent: IslandPresenting {
            func showLevel(_ level: IslandLevel) {}
            func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) {}
            func end(notice id: String) {}
            func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {}
            func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
        }
        let context = NotchcastContext(
            defaults: defaults, preferences: NotchcastPreferences(defaults: defaults, switches: SpotifyAddon.switches),
            presenter: Silent(), hub: hub, transcription: NotchcastTranscriptionRunner(dictation: FakeDictation()),
            now: { Date() }, onTapsChanged: {})
        guard let module = SpotifyAddon.makeModule(context) as? SpotifyModule else { preconditionFailure("module") }
        let covers = SpotifyCovers(send: system.web.send)

        let song = IslandMedia(id: "a", title: "Paper Lanterns", subtitle: "Juno Vale", artwork: cover,
                               isPlaying: true)
        var paused = song
        paused.isPlaying = false
        var long = song
        long.title = "Paper Lanterns (Live at the Harbour Hall, Remastered)"
        long.subtitle = "Juno Vale, The Night Ferry Orchestra"
        var scrolling = long
        scrolling.overflow = .scroll
        var loading = song
        loading.artwork = nil
        for notched in [false, true] {
            let form = notched ? "notch" : "nonotch"
            func art(_ media: IslandMedia) -> MediaGlanceArt {
                MediaGlanceArt(media, notch: notched, frosted: frosted, reducedMotion: false)
            }
            compact("b01-closed-playing-\(form)-\(look)", art(song), notched: notched)
            compact("b02-closed-paused-\(form)-\(look)", art(paused), notched: notched)
            compact("b03-closed-long-fit-\(form)-\(look)", art(long), notched: notched)
            compact("b04-closed-long-scroll-\(form)-\(look)", art(scrolling), notched: notched)
            compact("b05-closed-cover-loading-\(form)-\(look)", art(loading), notched: notched)
            if notched {
                let expansion = IslandExpansionArt(song, frosted: frosted)
                island("b06-song-change-\(form)-\(look)", width: max(expansion.size.width, notch.width + 104),
                       body: expansion.size.height, notched: true, radius: Theme.Radius.panel) { expansion.draw(in: $0) }
                let cut = IslandExpansionArt(long, frosted: frosted)
                island("b07-song-change-long-\(form)-\(look)", width: max(cut.size.width, notch.width + 104),
                       body: cut.size.height, notched: true, radius: Theme.Radius.panel) { cut.draw(in: $0) }
            }
            module.apply(playback(title: "Paper Lanterns", artists: ["Juno Vale"], playing: true, at: 87_000))
            page("b08-player-playing-\(form)-\(look)", notched: notched, module: module, covers: covers)
            module.apply(playback(title: long.title, artists: ["Juno Vale", "The Night Ferry Orchestra"],
                                  playing: false, at: 150_000))
            page("b09-player-paused-long-\(form)-\(look)", notched: notched, module: module, covers: covers)
            module.apply(SpotifyPlayback())
            page("b10-player-empty-\(form)-\(look)", notched: notched, module: module, covers: covers)
        }
        print("Spotify island renders: \(folder.path)")
    }
}
