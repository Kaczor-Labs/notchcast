import Foundation

/// The transcription form: a `file` part plus optional `language` and `response_format`.
struct DictationServerUpload: Equatable, Sendable {
    enum Format: Equatable, Sendable { case json, text }

    static let extensions: Set<String> = ["flac", "m4a", "mp3", "mp4", "mpeg", "mpga", "oga", "ogg", "wav", "webm"]

    var audio: Data
    /// From the part's filename, so the decoder gets its type hint; nil leaves it to sniffing.
    var fileExtension: String?
    var language: DictationLanguage?
    var format: Format

    /// `model` and any other field are ignored: the user's own Dictation model answers.
    static func parse(_ body: Data, boundary: String) -> Result<Self, DictationServerResponse> {
        guard let parts = parts(of: body, boundary: boundary) else {
            return .failure(.error(400, "Malformed multipart/form-data body."))
        }
        guard let file = parts.first(where: { $0.name == "file" }), !file.content.isEmpty else {
            return .failure(.error(400, "Attach the audio as a non-empty `file` field."))
        }
        guard file.content.count <= DictationServerHTTP.maximumFileBytes else { return .failure(.tooLarge) }
        guard isAudioContainer(file.content) else { return .failure(.unsupportedFormat) }
        var fileExtension: String?
        if let filename = file.filename, let dot = filename.lastIndex(of: ".") {
            let suffix = filename[filename.index(after: dot)...].lowercased()
            guard extensions.contains(suffix) else { return .failure(.unsupportedFormat) }
            fileExtension = suffix
        }
        var language: DictationLanguage?
        if let code = text(of: "language", in: parts), !code.isEmpty {
            guard let match = DictationLanguage.allCases.first(where: { $0.code == code }) else {
                return .failure(.error(400, "Unsupported language; send an ISO-639-1 code such as en or pl."))
            }
            language = match
        }
        let format: Format
        switch text(of: "response_format", in: parts) {
        case nil, "", "json": format = .json
        case "text": format = .text
        default: return .failure(.error(400, "response_format must be json or text."))
        }
        return .success(Self(audio: file.content, fileExtension: fileExtension, language: language, format: format))
    }

    /// The decoder sniffs content whatever the name says, so only the allowed containers reach it.
    static func isAudioContainer(_ data: Data) -> Bool {
        let bytes = Array(data.prefix(12))
        func has(_ text: String, at offset: Int) -> Bool {
            let wanted = Array(text.utf8)
            return bytes.count >= offset + wanted.count && Array(bytes[offset..<offset + wanted.count]) == wanted
        }
        if has("RIFF", at: 0), has("WAVE", at: 8) { return true }
        if has("fLaC", at: 0) || has("OggS", at: 0) || has("ID3", at: 0) || has("ftyp", at: 4) { return true }
        if bytes.starts(with: [0x1A, 0x45, 0xDF, 0xA3]) { return true }
        return bytes.count >= 2 && bytes[0] == 0xFF && bytes[1] & 0xE0 == 0xE0
    }

    /// Refuses audio that is unreadable or too long before it waits for the model.
    static func refusal(frames: Int64, sampleRate: Double) -> DictationServerResponse? {
        guard sampleRate > 0, frames > 0 else { return .unreadable }
        return Double(frames) / sampleRate > Double(DictationServerHTTP.maximumAudioSeconds) ? .tooLong : nil
    }

    /// Staged uploads a crash left behind; run before any listener starts, so none is in use.
    static func removeStaged(in directory: URL, prefix: String) {
        let manager = FileManager.default
        let names = (try? manager.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
        for name in names where name.hasPrefix(prefix) {
            try? manager.removeItem(at: directory.appending(path: name))
        }
    }

    private struct Part {
        var name: String
        var filename: String?
        var content: Data
    }

    private static func text(of name: String, in parts: [Part]) -> String? {
        parts.first { $0.name == name }.map {
            (String(bytes: $0.content, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    }

    /// RFC 7578 parts in order; nil when the body does not follow the boundary's framing.
    private static func parts(of body: Data, boundary: String) -> [Part]? {
        let delimiter = Data("--\(boundary)".utf8)
        let separator = Data("\r\n--\(boundary)".utf8)
        let lineBreak = Data("\r\n".utf8)
        let headEnd = Data("\r\n\r\n".utf8)
        guard body.starts(with: delimiter) else { return nil }
        var cursor = body.startIndex + delimiter.count
        var parts: [Part] = []
        while true {
            guard body.endIndex - cursor >= 2 else { return nil }
            let marker = body[cursor..<cursor + 2]
            if marker == Data("--".utf8) { return parts }
            guard marker == lineBreak else { return nil }
            cursor += 2
            guard let head = body.range(of: headEnd, in: cursor..<body.endIndex),
                let fields = String(data: body[cursor..<head.lowerBound], encoding: .utf8),
                let next = body.range(of: separator, in: head.upperBound..<body.endIndex)
            else { return nil }
            if let disposition = disposition(fields) {
                parts.append(
                    Part(name: disposition.name, filename: disposition.filename,
                         content: Data(body[head.upperBound..<next.lowerBound])))
            }
            cursor = next.upperBound
        }
    }

    private static func disposition(_ fields: String) -> (name: String, filename: String?)? {
        let line = fields.components(separatedBy: "\r\n").first {
            $0.lowercased().hasPrefix("content-disposition:")
        }
        guard let line else { return nil }
        var parameters: [String: String] = [:]
        for item in line.split(separator: ";").dropFirst() {
            let pair = item.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else { continue }
            var value = pair[1].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") { value = String(value.dropFirst().dropLast()) }
            parameters[pair[0].trimmingCharacters(in: .whitespaces).lowercased()] = value
        }
        guard let name = parameters["name"] else { return nil }
        return (name, parameters["filename"])
    }
}

/// A connection's bytes fed in as they arrive; it answers as soon as the request is decided.
struct DictationServerReader: Sendable {
    enum Step: Equatable, Sendable {
        case more
        /// The client sent `Expect: 100-continue` and waits for this before the body.
        case sendContinue
        case models
        case form(body: Data, boundary: String)
        case respond(DictationServerResponse)
    }

    private static let chunkBytes = 1 << 20

    private let token: String
    private let port: Int
    private var buffer = Data()
    private var pending: (length: Int, boundary: String)?

    init(token: String, port: Int) {
        self.token = token
        self.port = port
    }

    /// The head arrived and was accepted; only the body is still to come.
    var hasHead: Bool { pending != nil }

    /// The most a single receive should take: the rest of the body, or a head-sized read.
    var wanted: Int {
        guard let pending else { return 64 << 10 }
        return min(max(pending.length - buffer.count, 1), Self.chunkBytes)
    }

    mutating func feed(_ chunk: Data) -> Step {
        buffer.append(chunk)
        if pending != nil { return body() }
        switch DictationServerHTTP.parseHead(buffer) {
        case .incomplete: return .more
        case .rejected(let response): return .respond(response)
        case .complete(let head, let bodyStart):
            switch DictationServerHTTP.route(head, token: token, port: port) {
            case .models: return .models
            case .respond(let response): return .respond(response)
            case .form(let length, let boundary):
                buffer = buffer.subdata(in: buffer.startIndex + bodyStart..<buffer.endIndex)
                buffer.reserveCapacity(length)
                pending = (length, boundary)
                let step = body()
                guard step == .more, head.fields["expect"]?.lowercased() == "100-continue" else { return step }
                return .sendContinue
            }
        }
    }

    private func body() -> Step {
        guard let pending, buffer.count >= pending.length else { return .more }
        return .form(body: buffer.prefix(pending.length), boundary: pending.boundary)
    }
}
