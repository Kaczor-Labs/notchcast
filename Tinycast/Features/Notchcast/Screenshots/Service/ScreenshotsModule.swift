import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Runs one capture session at a time; a trigger while one is active is ignored.
@MainActor
final class ScreenshotsModule: NotchcastModule {
    enum Scope { case area, display, text }

    static let switchID = ScreenshotsAddon.switches[0].id
    static let textSymbol = "text.viewfinder"
    private let context: NotchcastContext
    private let system: ScreenshotSystem
    private let exclusion: ScreenshotExclusion
    private var running = false
    private var session: Task<Void, Never>?
    private var operation: UUID?
    private var closeSurface: (@MainActor () -> Void)?

    init(context: NotchcastContext, system: ScreenshotSystem,
         exclusion: ScreenshotExclusion = ScreenshotExclusion(
            pid: ProcessInfo.processInfo.processIdentifier, bundleID: Bundle.main.bundleIdentifier)) {
        self.context = context
        self.system = system
        self.exclusion = exclusion
    }

    func start() { running = true }

    func stop() {
        running = false
        operation = nil
        session?.cancel()
        session = nil
        closeSurface?()
    }

    func captureArea() { begin(.area) }

    func captureDisplay() { begin(.display) }

    func captureText() { begin(.text) }

    private func begin(_ scope: Scope) {
        guard running, session == nil else { return }
        guard system.grantAccess() else {
            if scope == .text { system.openScreenRecordingSettings() }
            return report(ScreenshotRequest.Failure.permissionDenied)
        }
        let id = UUID()
        operation = id
        session = Task {
            do {
                if let image = try await image(for: scope) {
                    if scope == .text {
                        try await copyText(in: image)
                    } else {
                        try await output(Self.png(image))
                    }
                }
            } catch {
                if operation == id, !(error is CancellationError) { report(error) }
            }
            guard operation == id else { return }
            operation = nil
            session = nil
        }
    }

    private func image(for scope: Scope) async throws -> CGImage? {
        switch scope {
        case .display:
            guard let display = try await system.freeze(system.cursor(), exclusion).first else {
                throw ScreenshotRequest.Failure.targetUnavailable
            }
            return display.image
        case .area, .text:
            let frozen = try await system.freeze(nil, exclusion)
            try Task.checkCancellation()
            let pickable = exclusion.pickable(system.windows())
            let windows = try await system.freezeWindows(pickable.map(\.id))
            try Task.checkCancellation()
            guard let request = await select(frozen, pickable.filter { windows[$0.id] != nil }) else { return nil }
            try Task.checkCancellation()
            return try image(for: request, in: frozen, windows: windows)
        }
    }

    private func select(_ frozen: [ScreenshotFrozenDisplay], _ windows: [ScreenshotWindow]) async
        -> ScreenshotRequest? {
        await withCheckedContinuation { continuation in
            closeSurface = system.select(frozen, windows) { [weak self] request in
                self?.closeSurface = nil
                continuation.resume(returning: request)
            }
        }
    }

    private func image(for request: ScreenshotRequest, in frozen: [ScreenshotFrozenDisplay],
                       windows: [UInt32: CGImage]) throws -> CGImage {
        switch request {
        case .rect(let rect):
            guard ScreenshotRequest.isValid(rect: rect) else { throw ScreenshotRequest.Failure.invalidRect }
            guard let display = frozen.first(where: { $0.frame.contains(rect) }),
                let image = ScreenshotGeometry.crop(display, to: rect)
            else { throw ScreenshotRequest.Failure.targetUnavailable }
            return image
        case .window(let id):
            guard let image = windows[id] else { throw ScreenshotRequest.Failure.targetUnavailable }
            return image
        case .display(let id):
            guard let display = frozen.first(where: { $0.id == id }) else {
                throw ScreenshotRequest.Failure.targetUnavailable
            }
            return display.image
        }
    }

    /// v1's order: the file first, so a failed clipboard write still leaves the picture saved.
    private func output(_ data: Data) async throws {
        let defaults = context.defaults
        let destination = defaults.string(forKey: ScreenshotBackupKeys.destination)
            .flatMap(ScreenshotDestination.init(rawValue:)) ?? .clipboard
        var saved: URL?
        if destination != .clipboard {
            let folder = try defaults.string(forKey: ScreenshotBackupKeys.folder)
                .map { URL(filePath: $0, directoryHint: .isDirectory) } ?? system.desktop()
            saved = try await Self.save(data, in: folder, date: context.now(), timeZone: .current)
        }
        try Task.checkCancellation()
        if destination != .file, !system.writeClipboard(data), saved == nil {
            throw ScreenshotRequest.Failure.clipboardFailed
        }
    }

    /// Only the text leaves: the image stays in memory and is never written to disk.
    private func copyText(in image: CGImage) async throws {
        let lines = try await system.recognizeText(image)
        try Task.checkCancellation()
        guard let text = ScreenText.join(lines) else { throw ScreenshotRequest.Failure.noText }
        guard system.writeText(text) else { throw ScreenshotRequest.Failure.clipboardFailed }
        context.presenter.post(IslandNotice(
            id: "screenshot.text", symbol: Self.textSymbol, text: ScreenText.firstLine(of: text)), onTap: nil)
    }

    private func report(_ error: any Error) {
        context.presenter.post(IslandNotice(
            id: "screenshot.failed", symbol: "camera", text: ScreenshotRequest.failureMessage(error),
            isFailure: true), onTap: nil)
    }

    @concurrent
    private static func png(_ image: CGImage) async throws -> Data {
        let data = NSMutableData()
        guard let encoder = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw ScreenshotRequest.Failure.encodingFailed
        }
        CGImageDestinationAddImage(encoder, image, nil)
        guard CGImageDestinationFinalize(encoder) else { throw ScreenshotRequest.Failure.encodingFailed }
        return data as Data
    }

    @concurrent
    static func save(_ data: Data, in folder: URL, date: Date, timeZone: TimeZone) async throws -> URL {
        var collision = 0
        while true {
            try Task.checkCancellation()
            let url = folder.appending(
                path: ScreenshotFileName.name(date: date, timeZone: timeZone, collision: collision))
            do {
                try data.write(to: url, options: .withoutOverwriting)
                return url
            } catch CocoaError.fileWriteFileExists {
                collision += 1
            }
        }
    }
}
