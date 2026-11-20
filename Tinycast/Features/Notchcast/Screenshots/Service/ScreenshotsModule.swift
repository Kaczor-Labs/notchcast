import Foundation
import ImageIO

/// Runs one capture or edit at a time; a trigger while one is active, the editor included, is ignored.
@MainActor
final class ScreenshotsModule: NotchcastModule {
    enum Scope { case area, display, text }

    static let switchID = ScreenshotsAddon.switches[0].id
    static let editAfterCaptureKey = "notchcast.screenshot.editAfterCapture"
    static let textSymbol = "text.viewfinder"
    static let textNoticeID = "screenshot.text"
    private let context: NotchcastContext
    private let system: ScreenshotSystem
    private let exclusion: ScreenshotExclusion
    private var running = false
    private var session: Task<Void, Never>?
    private var operation: UUID?
    private var closeSurface: (@MainActor () -> Void)?
    /// The last capture as PNG, so Edit Last Screenshot never holds a full bitmap between edits.
    private var lastCapture: (png: Data, scale: CGFloat)?
    private var closeEditor: (@MainActor () -> Void)?
    private var export: Task<Void, Never>?
    private var warmUp: Task<Void, Never>?

    init(context: NotchcastContext, system: ScreenshotSystem,
         exclusion: ScreenshotExclusion = ScreenshotExclusion(
            pid: ProcessInfo.processInfo.processIdentifier, bundleID: Bundle.main.bundleIdentifier)) {
        self.context = context
        self.system = system
        self.exclusion = exclusion
    }

    func start() {
        running = true
        let warm = system.warmTextRecognition
        warmUp = Task.detached(priority: .utility) { await warm() }
    }

    func stop() {
        running = false
        operation = nil
        session?.cancel()
        session = nil
        warmUp?.cancel()
        warmUp = nil
        context.presenter.end(notice: Self.textNoticeID)
        closeSurface?()
        export?.cancel()
        export = nil
        endEditing()
        lastCapture = nil
    }

    func captureArea() { begin(.area) }

    func captureDisplay() { begin(.display) }

    func captureText() { begin(.text) }

    func editLastCapture() {
        guard isIdle else { return }
        guard let lastCapture else { return report(ScreenshotRequest.Failure.nothingToEdit) }
        run { [self] in
            guard let image = await Self.decode(lastCapture.png) else {
                throw ScreenshotRequest.Failure.encodingFailed
            }
            try Task.checkCancellation()
            edit(image, scale: lastCapture.scale)
        }
    }

    private var isIdle: Bool { running && session == nil && closeEditor == nil }

    private func begin(_ scope: Scope) {
        guard isIdle else { return }
        guard system.grantAccess() else {
            if scope == .text { system.openScreenRecordingSettings() }
            return report(ScreenshotRequest.Failure.permissionDenied)
        }
        run { [self] in
            guard let shot = try await capture(scope) else { return }
            if scope == .text { return try await copyText(in: shot.image) }
            let data = try await Self.png(shot.image, scale: shot.scale)
            try Task.checkCancellation()
            lastCapture = (data, shot.scale)
            if context.defaults.bool(forKey: Self.editAfterCaptureKey) {
                edit(shot.image, scale: shot.scale)
            } else {
                try await output(data)
            }
        }
    }

    private func run(_ work: @escaping @MainActor @Sendable () async throws -> Void) {
        let id = UUID()
        operation = id
        session = Task {
            do {
                try await work()
            } catch {
                if operation == id, !(error is CancellationError) { report(error) }
            }
            guard operation == id else { return }
            operation = nil
            session = nil
        }
    }

    /// The picture with its pixels per point, read from the display it was frozen on.
    private func capture(_ scope: Scope) async throws -> (image: CGImage, scale: CGFloat)? {
        switch scope {
        case .display:
            guard let display = try await system.freeze(system.cursor(), exclusion).first else {
                throw ScreenshotRequest.Failure.targetUnavailable
            }
            return (display.image, display.scale)
        case .area, .text:
            let frozen = try await system.freeze(nil, exclusion)
            try Task.checkCancellation()
            let pickable = exclusion.pickable(system.windows())
            let windows = try await system.freezeWindows(pickable.map(\.id))
            try Task.checkCancellation()
            let offered = pickable.filter { windows[$0.id] != nil }
            guard let request = await select(frozen, offered) else { return nil }
            try Task.checkCancellation()
            return try capture(request, in: frozen, windows: windows, frames: offered)
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

    private func capture(
        _ request: ScreenshotRequest, in frozen: [ScreenshotFrozenDisplay], windows: [UInt32: CGImage],
        frames: [ScreenshotWindow]
    ) throws -> (image: CGImage, scale: CGFloat) {
        switch request {
        case .rect(let rect):
            guard ScreenshotRequest.isValid(rect: rect) else { throw ScreenshotRequest.Failure.invalidRect }
            guard let display = frozen.first(where: { $0.frame.contains(rect) }),
                let image = ScreenshotGeometry.crop(display, to: rect)
            else { throw ScreenshotRequest.Failure.targetUnavailable }
            return (image, display.scale)
        case .window(let id):
            guard let image = windows[id] else { throw ScreenshotRequest.Failure.targetUnavailable }
            let points = frames.first { $0.id == id }?.frame.width ?? 0
            return (image, points > 0 ? max(1, (CGFloat(image.width) / points).rounded()) : 1)
        case .display(let id):
            guard let display = frozen.first(where: { $0.id == id }) else {
                throw ScreenshotRequest.Failure.targetUnavailable
            }
            return (display.image, display.scale)
        }
    }

    private func edit(_ image: CGImage, scale: CGFloat) {
        closeEditor = system.edit(image, scale) { [weak self] outcome in self?.finishEditing(outcome) }
    }

    /// The editor stays open until its result is written, so a failed write loses no annotation.
    private func finishEditing(_ outcome: CaptureEditorOutcome) {
        guard closeEditor != nil, export == nil else { return }
        let document: AnnotationDocument
        switch outcome {
        case .discard: return endEditing()
        case .copy(let edited), .save(let edited): document = edited
        }
        export = Task {
            do {
                let data = try await Self.render(document)
                try Task.checkCancellation()
                if case .save = outcome {
                    _ = try await Self.save(data, in: folder(), date: context.now(), timeZone: .current)
                } else if !system.writeClipboard(data) {
                    throw ScreenshotRequest.Failure.clipboardFailed
                }
                try Task.checkCancellation()
                endEditing()
            } catch {
                if !(error is CancellationError) { report(error) }
            }
            if !Task.isCancelled { export = nil }
        }
    }

    private func endEditing() {
        let close = closeEditor
        closeEditor = nil
        close?()
    }

    private func folder() throws -> URL {
        try context.defaults.string(forKey: ScreenshotBackupKeys.folder)
            .map { URL(filePath: $0, directoryHint: .isDirectory) } ?? system.desktop()
    }

    /// v1's order: the file first, so a failed clipboard write still leaves the picture saved.
    private func output(_ data: Data) async throws {
        let destination = context.defaults.string(forKey: ScreenshotBackupKeys.destination)
            .flatMap(ScreenshotDestination.init(rawValue:)) ?? .clipboard
        var saved: URL?
        if destination != .clipboard {
            saved = try await Self.save(data, in: folder(), date: context.now(), timeZone: .current)
        }
        try Task.checkCancellation()
        if destination != .file, !system.writeClipboard(data), saved == nil {
            throw ScreenshotRequest.Failure.clipboardFailed
        }
    }

    /// Only the text leaves: the image stays in memory and is never written to disk.
    /// Reposting the progress notice's id with the first line turns it into the result in place.
    private func copyText(in image: CGImage) async throws {
        context.presenter.post(IslandNotice(
            id: Self.textNoticeID, symbol: Self.textSymbol,
            text: String(localized: "Recognizing text…", table: "NotchcastScreenshots"),
            progress: IslandProgress(fraction: nil)), onTap: nil)
        let text: String
        do {
            await warmUp?.value
            try Task.checkCancellation()
            let lines = try await system.recognizeText(image)
            try Task.checkCancellation()
            guard let joined = ScreenText.join(lines) else { throw ScreenshotRequest.Failure.noText }
            guard system.writeText(joined) else { throw ScreenshotRequest.Failure.clipboardFailed }
            text = joined
        } catch {
            // A cancelled run belongs to a `stop()` that already ended it, maybe under a newer notice.
            if !Task.isCancelled { context.presenter.end(notice: Self.textNoticeID) }
            throw error
        }
        context.presenter.post(IslandNotice(
            id: Self.textNoticeID, symbol: Self.textSymbol, text: ScreenText.firstLine(of: text)), onTap: nil)
    }

    private func report(_ error: any Error) {
        context.presenter.post(IslandNotice(
            id: "screenshot.failed", symbol: "camera", text: ScreenshotRequest.failureMessage(error),
            isFailure: true), onTap: nil)
    }

    @concurrent
    private static func png(_ image: CGImage, scale: CGFloat) async throws -> Data {
        do {
            return try AnnotationRenderer.png(image, scale: scale)
        } catch {
            throw ScreenshotRequest.Failure.encodingFailed
        }
    }

    @concurrent
    private static func render(_ document: AnnotationDocument) async throws -> Data {
        do {
            return try AnnotationRenderer.png(document.finished())
        } catch {
            throw ScreenshotRequest.Failure.encodingFailed
        }
    }

    @concurrent
    private static func decode(_ data: Data) async -> CGImage? {
        CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
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
