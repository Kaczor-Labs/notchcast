import AVFoundation
import Foundation
import Network
import Observation
import Synchronization

/// Lends the user's Dictation model to other apps on 127.0.0.1, behind a bearer token.
@MainActor
@Observable
final class DictationServer {
    enum Status: Equatable {
        case off, starting, listening
        case failed(String)
    }

    static let defaultPort = 8178
    static let ports = 1024...65535
    private static let enabledKey = "dictationServerEnabled"
    private static let portKey = "dictationServerPort"
    private static let maximumConnections = 8
    /// Keyed by the bundle, so a Debug build's sweep never removes an installed copy's upload.
    private nonisolated static let stagedPrefix = "\(Bundle.main.bundleIdentifier ?? "notchcast").dictation-request-"
    /// The endpoint has one token, so it lives under one fixed account.
    private static let tokenAccount = UUID(
        uuid: (0x6D, 0x1C, 0x4B, 0x0E, 0x5F, 0x2A, 0x4C, 0x55, 0x9A, 0x8E, 0x0B, 0x7D, 0x3F, 0x1E, 0x2C, 0x94))

    private(set) var status: Status = .off
    private(set) var token: String?
    /// The listener keeps serving the old token, so this is reported apart from `status`.
    private(set) var tokenFailure: String?
    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.enabledKey)
            apply()
        }
    }
    var port: Int {
        didSet {
            defaults.set(port, forKey: Self.portKey)
            apply()
        }
    }

    var baseURL: String { "http://127.0.0.1:\(port)/v1" }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let coordinator: DictationCoordinator
    @ObservationIgnored private let runner: NotchcastTranscriptionRunner
    @ObservationIgnored private let queue = DictationServerQueue(capacity: DictationServer.maximumConnections)
    @ObservationIgnored private let clients = DictationServerClients(capacity: DictationServer.maximumConnections)
    @ObservationIgnored private let tokens = KeychainSecretStore.dictationServer
    @ObservationIgnored private var watcher: Task<Void, Never>?
    @ObservationIgnored private var listening: Task<Void, Never>?
    @ObservationIgnored private var listeningPort: Int?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var dictationOn = false

    /// `defaults` is the fork's own suite, which backups and `settings.json` never carry.
    init(
        defaults: UserDefaults, settings: AppSettings, coordinator: DictationCoordinator,
        runner: NotchcastTranscriptionRunner
    ) {
        self.defaults = defaults
        self.settings = settings
        self.coordinator = coordinator
        self.runner = runner
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        let stored = defaults.integer(forKey: Self.portKey)
        port = Self.ports.contains(stored) ? stored : Self.defaultPort
    }

    func start() {
        guard watcher == nil else { return }
        let settings = settings
        let coordinator = coordinator
        watcher = Task { [weak self] in
            await Self.removeStaged()
            for await (enabled, dictating) in Observations({ (settings.dictationEnabled, coordinator.isActive) }) {
                guard let self else { return }
                queue.setUserDictating(dictating)
                guard dictationOn != enabled else { continue }
                dictationOn = enabled
                apply()
            }
        }
    }

    func stop() {
        watcher?.cancel()
        watcher = nil
        dictationOn = false
        apply()
    }

    func regenerateToken() {
        var generator = SystemRandomNumberGenerator()
        let fresh = DictationServerHTTP.makeToken(using: &generator)
        do {
            try tokens.setSecret(fresh, for: Self.tokenAccount)
            token = fresh
            tokenFailure = nil
        } catch {
            tokenFailure = String(
                localized: "Notchcast could not save a new token in the Keychain. The current token still works.",
                table: "Notchcast")
        }
    }

    /// Serves only while this switch and Dictation itself are on.
    private func apply() {
        guard isEnabled, dictationOn else {
            stopListening()
            status = .off
            return
        }
        guard listening == nil || listeningPort != port else { return }
        stopListening()
        guard let token = token ?? storedToken() else {
            status = .failed(String(localized: "Notchcast could not read its token from the Keychain.", table: "Notchcast"))
            return
        }
        self.token = token
        listen(on: port)
    }

    /// Generated on first use and kept in the Keychain; never logged or written anywhere else.
    private func storedToken() -> String? {
        do {
            if let stored = try tokens.secret(for: Self.tokenAccount) { return stored }
            var generator = SystemRandomNumberGenerator()
            let fresh = DictationServerHTTP.makeToken(using: &generator)
            try tokens.setSecret(fresh, for: Self.tokenAccount)
            return fresh
        } catch {
            return nil
        }
    }

    private func listen(on port: Int) {
        guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else {
            return failed(generation)
        }
        let generation = UUID()
        self.generation = generation
        listeningPort = port
        status = .starting
        listening = Task { [weak self] in
            do {
                let listener = try DictationServerListener.make(port: endpointPort)
                try await listener.onStateUpdate { [weak self] _, state in
                    switch state {
                    case .ready: self?.ready(generation)
                    case .waiting, .failed: self?.failed(generation)
                    default: break
                    }
                }.run { [weak self] connection in
                    await self?.serve(connection, port: port)
                }
            } catch {
                if !Task.isCancelled { self?.failed(generation) }
            }
        }
    }

    private func stopListening() {
        generation = UUID()
        listening?.cancel()
        listening = nil
        listeningPort = nil
    }

    private func ready(_ generation: UUID) {
        guard generation == self.generation else { return }
        status = .listening
    }

    private func failed(_ generation: UUID) {
        guard generation == self.generation else { return }
        let port = listeningPort ?? port
        stopListening()
        status = .failed(
            String(localized: "Could not listen on port \(port). Another app may be using it.", table: "Notchcast"))
    }

    private func serve(_ connection: NetworkConnection<TCP>, port: Int) async {
        guard let token, clients.admit() else { return }
        defer { clients.release() }
        let reader = DictationServerReader(token: token, port: port)
        let progress = HeadProgress()
        let step: DictationServerReader.Step
        do {
            step = try await withThrowingTaskGroup(of: DictationServerReader.Step.self) { group in
                group.addTask { try await Self.read(connection, reader: reader, progress: progress) }
                group.addTask {
                    try await DictationServerHTTP.expire(headRead: { progress.isRead() }) { try await Task.sleep(for: $0) }
                    throw URLError(.timedOut)
                }
                defer { group.cancelAll() }
                return try await group.next() ?? .more
            }
        } catch {
            return
        }
        let response: DictationServerResponse
        switch step {
        case .models: response = .models([Self.modelID(settings.dictationModel)])
        case .form(let body, let boundary):
            await DictationServerListener.reply(connection) { [weak self] in
                let answer = await self?.transcribe(body, boundary: boundary)
                return (answer ?? .error(503, "Notchcast stopped sharing the model.")).encoded
            }
            return
        case .respond(let refusal): response = refusal
        case .more, .sendContinue: return
        }
        try? await connection.send(response.encoded, endOfStream: true)
    }

    /// Off the main actor: nothing an unauthenticated client sends is parsed there.
    @concurrent
    private nonisolated static func read(
        _ connection: NetworkConnection<TCP>, reader: DictationServerReader, progress: HeadProgress
    ) async throws -> DictationServerReader.Step {
        var reader = reader
        while true {
            let message = try await connection.receive(atLeast: 1, atMost: reader.wanted)
            let step = reader.feed(message.content)
            if reader.hasHead { progress.markRead() }
            switch step {
            case .more:
                if message.metadata.endOfStream { throw CancellationError() }
            case .sendContinue:
                try await connection.send(DictationServerResponse.continueHead, endOfStream: false)
            case let step:
                return step
            }
        }
    }

    private func transcribe(_ body: Data, boundary: String) async -> DictationServerResponse {
        let upload: DictationServerUpload
        switch await Self.parse(body, boundary: boundary) {
        case .success(let parsed): upload = parsed
        case .failure(let refusal): return refusal
        }
        guard coordinator.models.isInstalled(settings.dictationModel) else { return .modelMissing }
        guard let file = await Self.stage(upload) else { return .error(500, "Could not stage the audio.") }
        defer { try? FileManager.default.removeItem(at: file) }
        if let refusal = await Self.lengthRefusal(file) { return refusal }
        do {
            try await queue.enter()
        } catch is DictationServerQueue.Full {
            return .busy
        } catch {
            return .error(503, "Notchcast stopped sharing the model.")
        }
        defer { queue.leave() }
        do {
            let text = try await runner.transcribe(file, language: upload.language?.rawValue)
            return .transcript(text, format: upload.format)
        } catch let failure as NotchcastTranscribeError {
            switch failure {
            case .busy: return .busy
            case .unavailable: return .modelMissing
            case .unreadableAudio: return .unreadable
            case .failed: return .error(500, "Transcription failed.")
            }
        } catch {
            return .error(503, "Notchcast stopped sharing the model.")
        }
    }

    @concurrent
    private nonisolated static func parse(_ body: Data, boundary: String) async
        -> Result<DictationServerUpload, DictationServerResponse>
    {
        DictationServerUpload.parse(body, boundary: boundary)
    }

    /// The decoder reads a file, so the upload lives in a private temporary one for the request only.
    @concurrent
    private nonisolated static func stage(_ upload: DictationServerUpload) async -> URL? {
        let name = stagedPrefix + UUID().uuidString + (upload.fileExtension.map { ".\($0)" } ?? "")
        let url = URL.temporaryDirectory.appending(path: name)
        let created = FileManager.default.createFile(
            atPath: url.path(percentEncoded: false), contents: upload.audio,
            attributes: [.posixPermissions: 0o600])
        return created ? url : nil
    }

    @concurrent
    private nonisolated static func lengthRefusal(_ file: URL) async -> DictationServerResponse? {
        guard let audio = try? AVAudioFile(forReading: file) else { return .unreadable }
        return DictationServerUpload.refusal(frames: audio.length, sampleRate: audio.fileFormat.sampleRate)
    }

    @concurrent
    private nonisolated static func removeStaged() async {
        DictationServerUpload.removeStaged(in: URL.temporaryDirectory, prefix: stagedPrefix)
    }

    private static func modelID(_ model: DictationModel) -> String {
        "\(model.family.rawValue)-\(model.variantTitle)".lowercased()
    }
}

/// Set once the reader has the head, so the deadline task knows which phase it is timing.
private final class HeadProgress: Sendable {
    private let read = Mutex(false)

    func markRead() { read.withLock { $0 = true } }
    func isRead() -> Bool { read.withLock { $0 } }
}
