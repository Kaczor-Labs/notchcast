import Foundation

/// The shared-model endpoint's HTTP surface: one request per connection, decided from its head.
enum DictationServerHTTP {
    static let transcriptionsPath = "/v1/audio/transcriptions"
    static let modelsPath = "/v1/models"
    static let maximumHeadBytes = 16 << 10
    static let maximumFileBytes = 25 << 20
    /// Room for the form's boundaries and small fields around a file at the cap.
    static let maximumBodyBytes = maximumFileBytes + (64 << 10)
    static let retryAfterSeconds = 5

    struct Head: Equatable, Sendable {
        var method: String
        var path: String
        /// Lowercased field names.
        var fields: [String: String]
    }

    enum HeadParse: Equatable, Sendable {
        case incomplete
        case complete(Head, bodyStart: Int)
        case rejected(DictationServerResponse)
    }

    enum Route: Equatable, Sendable {
        case models
        case form(length: Int, boundary: String)
        case respond(DictationServerResponse)
    }

    /// Fields whose repetition would make framing or access ambiguous.
    private static let singleFields: Set<String> = [
        "authorization", "content-length", "content-type", "host", "transfer-encoding",
    ]

    static func parseHead(_ data: Data) -> HeadParse {
        guard let end = data.firstRange(of: Data("\r\n\r\n".utf8)) else {
            return data.count > maximumHeadBytes ? .rejected(.error(431, "Request headers are too large.")) : .incomplete
        }
        let malformed = HeadParse.rejected(.error(400, "Malformed request."))
        guard end.lowerBound - data.startIndex <= maximumHeadBytes,
            let text = String(data: data[data.startIndex..<end.lowerBound], encoding: .utf8)
        else { return malformed }
        var lines = text.components(separatedBy: "\r\n")
        let request = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: false)
        guard request.count == 3, request[2].hasPrefix("HTTP/1."), !request[0].isEmpty else { return malformed }
        var fields: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { return malformed }
            let name = line[..<colon].lowercased()
            guard !name.isEmpty, !name.contains(" ") else { return malformed }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if let existing = fields[name] {
                guard !singleFields.contains(name) else { return malformed }
                fields[name] = existing + ", " + value
            } else {
                fields[name] = value
            }
        }
        let path = request[1].split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let head = Head(method: String(request[0]), path: String(path), fields: fields)
        return .complete(head, bodyStart: end.upperBound - data.startIndex)
    }

    /// Host before token, so a rebinding page is refused without learning whether a token works.
    static func route(_ head: Head, token: String, port: Int) -> Route {
        guard isLoopbackHost(head.fields["host"], port: port) else {
            return .respond(.error(403, "Only 127.0.0.1 and localhost are served."))
        }
        guard authorized(head.fields["authorization"], token: token) else { return .respond(.unauthorized) }
        switch (head.method, head.path) {
        case ("GET", modelsPath): return .models
        case ("POST", transcriptionsPath): break
        case (_, modelsPath), (_, transcriptionsPath): return .respond(.error(405, "Method not allowed."))
        default: return .respond(.error(404, "Not found."))
        }
        guard head.fields["transfer-encoding"] == nil, let text = head.fields["content-length"],
            let length = Int(text), length >= 0
        else { return .respond(.error(411, "Send the request with a Content-Length.")) }
        guard length <= maximumBodyBytes else { return .respond(.tooLarge) }
        guard let boundary = boundary(head.fields["content-type"]) else {
            return .respond(.error(415, "Send the audio as multipart/form-data."))
        }
        return .form(length: length, boundary: boundary)
    }

    static func isLoopbackHost(_ host: String?, port: Int) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return ["127.0.0.1", "localhost"].contains { host == $0 || host == "\($0):\(port)" }
    }

    /// Runs over the whole expected token whatever the input, so timing reveals no matching prefix.
    static func authorized(_ field: String?, token: String) -> Bool {
        guard !token.isEmpty, let field else { return false }
        let parts = field.split(separator: " ", maxSplits: 1)
        guard parts.count == 2, parts[0].lowercased() == "bearer" else { return false }
        let given = Array(parts[1].trimmingCharacters(in: .whitespaces).utf8)
        let expected = Array(token.utf8)
        var difference = given.count ^ expected.count
        for index in expected.indices {
            difference |= Int(expected[index] ^ (index < given.count ? given[index] : 0))
        }
        return difference == 0
    }

    static func boundary(_ contentType: String?) -> String? {
        guard let parts = contentType?.split(separator: ";").map({ $0.trimmingCharacters(in: .whitespaces) }),
            parts.first?.lowercased() == "multipart/form-data"
        else { return nil }
        for part in parts.dropFirst() where part.lowercased().hasPrefix("boundary=") {
            var value = String(part.dropFirst("boundary=".count))
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") { value = String(value.dropFirst().dropLast()) }
            return (1...70).contains(value.utf8.count) ? value : nil
        }
        return nil
    }

    /// 32 bytes from `generator` as 64 hex digits.
    static func makeToken(using generator: inout some RandomNumberGenerator) -> String {
        (0..<32).map { _ in
            let byte = UInt8.random(in: .min ... .max, using: &generator)
            return String(byte >> 4, radix: 16) + String(byte & 0x0F, radix: 16)
        }.joined()
    }
}

/// One complete response; every connection closes after it.
struct DictationServerResponse: Error, Equatable, Sendable {
    var status: Int
    var contentType = "application/json"
    var body: Data
    var retryAfter: Int?

    static let continueHead = Data("HTTP/1.1 100 Continue\r\n\r\n".utf8)
    static let unauthorized = error(401, "Missing or wrong bearer token.")
    static let tooLarge = error(413, "The audio file is larger than 25 MB.")
    static let busy = error(
        503, "Notchcast's own dictation is using the model; retry shortly.",
        retryAfter: DictationServerHTTP.retryAfterSeconds)
    static let modelMissing = error(
        503, "No dictation model is installed. Download one in Notchcast's Dictation settings.")

    private struct Failure: Encodable {
        struct Detail: Encodable {
            let message: String
            let type: String
        }
        let error: Detail
    }

    private struct ModelList: Encodable {
        struct Entry: Encodable {
            let id: String
            var object = "model"
            var owned_by = "notchcast"
        }
        var object = "list"
        let data: [Entry]
    }

    static func error(_ status: Int, _ message: String, retryAfter: Int? = nil) -> Self {
        let type = status >= 500 ? "server_error" : "invalid_request_error"
        return Self(status: status, body: encode(Failure(error: .init(message: message, type: type))), retryAfter: retryAfter)
    }

    static func transcript(_ text: String, format: DictationServerUpload.Format) -> Self {
        switch format {
        case .json: Self(status: 200, body: encode(["text": text]))
        case .text: Self(status: 200, contentType: "text/plain; charset=utf-8", body: Data(text.utf8))
        }
    }

    static func models(_ ids: [String]) -> Self {
        Self(status: 200, body: encode(ModelList(data: ids.map { ModelList.Entry(id: $0) })))
    }

    var encoded: Data {
        var head = "HTTP/1.1 \(status) \(Self.reasons[status] ?? "Error")\r\n"
        head += "Content-Type: \(contentType)\r\nContent-Length: \(body.count)\r\n"
        head += "Cache-Control: no-store\r\nConnection: close\r\n"
        if status == 401 { head += "WWW-Authenticate: Bearer\r\n" }
        if let retryAfter { head += "Retry-After: \(retryAfter)\r\n" }
        return Data((head + "\r\n").utf8) + body
    }

    private static let reasons = [
        200: "OK", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found",
        405: "Method Not Allowed", 411: "Length Required", 413: "Content Too Large",
        415: "Unsupported Media Type", 431: "Request Header Fields Too Large", 500: "Internal Server Error",
        503: "Service Unavailable",
    ]

    private static func encode(_ value: some Encodable) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(value)) ?? Data("{}".utf8)
    }
}
