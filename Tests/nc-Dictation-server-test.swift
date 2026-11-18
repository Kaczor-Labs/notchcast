// notchcast-sources: Tinycast/Features/Dictation/Model/DictationServerHTTP.swift Tinycast/Features/Dictation/Model/DictationServerUpload.swift
// notchcast-sources: Tinycast/Features/Dictation/Model/DictationServerQueue.swift Tinycast/Features/Dictation/Model/DictationLanguage.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastTranscription.swift Tests/NotchcastDictationFixture.swift
import Foundation

/// A fixed byte stream, so token generation is checked without real randomness.
private struct CountingGenerator: RandomNumberGenerator {
    var state: UInt64 = 0
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        return state
    }
}

/// What the scheduling tasks did, readable after they ran.
@MainActor
private final class Log {
    var admitted = false
    var order: [Int] = []
}

@main
@MainActor
struct DictationServerTest {
    static var failures = 0
    static var checks = 0
    static let token = String(repeating: "ab", count: 32)
    static let port = 8178
    static let boundary = "XyZ123"

    static func check(_ label: String, _ ok: Bool) {
        checks += 1
        if !ok {
            failures += 1
            print("FAIL \(label)")
        }
    }

    static func main() async {
        parsesHeads()
        routes()
        authorizes()
        parsesForms()
        readsInChunks()
        encodesResponses()
        makesTokens()
        await queueWaitsForUser()
        await queueRunsInOrder()
        await queueRefusesWhenFull()
        await queueDropsCancelledWaiter()
        await userWinsRunningRequest()
        await passesLanguage()
        print(failures == 0 ? "PASS DictationServerTest (\(checks) checks)" : "FAILED \(failures)/\(checks)")
        if failures > 0 { exit(1) }
    }

    // MARK: HTTP

    static func head(_ lines: [String]) -> Data { Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8) }

    static func request(_ method: String = "POST", path: String = DictationServerHTTP.transcriptionsPath,
                        fields: [String] = []) -> DictationServerHTTP.Head? {
        guard case .complete(let parsed, _) = DictationServerHTTP.parseHead(head(["\(method) \(path) HTTP/1.1"] + fields))
        else { return nil }
        return parsed
    }

    static func status(_ route: DictationServerHTTP.Route) -> Int? {
        if case .respond(let response) = route { return response.status }
        return nil
    }

    static var goodFields: [String] {
        ["Host: 127.0.0.1:8178", "Authorization: Bearer \(token)", "Content-Length: 100",
         "Content-Type: multipart/form-data; boundary=\(boundary)"]
    }

    static func parsesHeads() {
        let partial = Data("GET / HTTP/1.1\r\nHost: x\r\n".utf8)
        check("head waits for its blank line", DictationServerHTTP.parseHead(partial) == .incomplete)
        let lines = ["GET /v1/models?x=1 HTTP/1.1", "HOST: localhost", "X-A: 1", "x-a: 2"]
        if case .complete(let value, let start) = DictationServerHTTP.parseHead(head(lines)) {
            check("query is dropped from the path", value.path == "/v1/models")
            check("field names are lowercased", value.fields["host"] == "localhost")
            check("repeated ordinary fields join", value.fields["x-a"] == "1, 2")
            check("body starts after the blank line", start == head(lines).count)
        } else {
            check("well-formed head parses", false)
        }
        let doubled = DictationServerHTTP.parseHead(head(["POST / HTTP/1.1", "Content-Length: 1", "Content-Length: 900"]))
        check("a repeated Content-Length is refused", doubled == .rejected(.error(400, "Malformed request.")))
        check("a request line without a version is refused",
              DictationServerHTTP.parseHead(head(["GET /"])) == .rejected(.error(400, "Malformed request.")))
        check("a field without a colon is refused",
              DictationServerHTTP.parseHead(head(["GET / HTTP/1.1", "junk"])) == .rejected(.error(400, "Malformed request.")))
        let flood = Data(repeating: UInt8(ascii: "a"), count: DictationServerHTTP.maximumHeadBytes + 1)
        if case .rejected(let response) = DictationServerHTTP.parseHead(flood) {
            check("an endless head is cut off at the cap", response.status == 431)
        } else {
            check("an endless head is cut off at the cap", false)
        }
    }

    static func routes() {
        func route(_ method: String = "POST", path: String = DictationServerHTTP.transcriptionsPath,
                   fields: [String]) -> DictationServerHTTP.Route {
            guard let parsed = request(method, path: path, fields: fields) else { return .respond(.error(0, "")) }
            return DictationServerHTTP.route(parsed, token: token, port: port)
        }
        check("a complete upload head becomes a form",
              route(fields: goodFields) == .form(length: 100, boundary: boundary))
        check("models needs only host and token",
              route("GET", path: DictationServerHTTP.modelsPath, fields: Array(goodFields.prefix(2))) == .models)
        let noToken = goodFields.filter { !$0.hasPrefix("Authorization") }
        check("no token is 401", status(route(fields: noToken)) == 401)
        check("a wrong token is 401",
              status(route(fields: noToken + ["Authorization: Bearer \(String(repeating: "ab", count: 31))ac"])) == 401)
        check("no token on an unknown path is still 401, not 404",
              status(route(path: "/admin", fields: noToken)) == 401)
        let foreignHost = ["Host: evil.example:8178"] + goodFields.dropFirst()
        check("a rebinding host is refused before the token", status(route(fields: foreignHost)) == 403)
        check("a missing host is refused", status(route(fields: Array(goodFields.dropFirst()))) == 403)
        check("localhost without a port is served",
              route(fields: ["Host: localhost"] + goodFields.dropFirst()) == .form(length: 100, boundary: boundary))
        check("an unknown path is 404", status(route(path: "/v1/chat", fields: goodFields)) == 404)
        check("a wrong method is 405", status(route("GET", fields: goodFields)) == 405)
        let chunked = goodFields.filter { !$0.hasPrefix("Content-Length") } + ["Transfer-Encoding: chunked"]
        check("a chunked upload is 411", status(route(fields: chunked)) == 411)
        let negative = goodFields.map { $0.hasPrefix("Content-Length") ? "Content-Length: -4" : $0 }
        check("a negative length is 411", status(route(fields: negative)) == 411)
        let huge = goodFields.map {
            $0.hasPrefix("Content-Length") ? "Content-Length: \(DictationServerHTTP.maximumBodyBytes + 1)" : $0
        }
        check("an oversized body is 413 before it is read", status(route(fields: huge)) == 413)
        let json = goodFields.map { $0.hasPrefix("Content-Type") ? "Content-Type: application/json" : $0 }
        check("a non-form body is 415", status(route(fields: json)) == 415)
        check("a quoted boundary is unquoted",
              DictationServerHTTP.boundary("multipart/form-data; charset=utf-8; boundary=\"a b\"") == "a b")
        check("an over-long boundary is refused",
              DictationServerHTTP.boundary("multipart/form-data; boundary=\(String(repeating: "b", count: 71))") == nil)
    }

    static func authorizes() {
        check("bearer scheme is case-insensitive", DictationServerHTTP.authorized("bearer \(token)", token: token))
        check("a prefix of the token fails", !DictationServerHTTP.authorized("Bearer \(token.dropLast())", token: token))
        check("a longer token fails", !DictationServerHTTP.authorized("Bearer \(token)0", token: token))
        check("basic auth fails", !DictationServerHTTP.authorized("Basic \(token)", token: token))
        check("an empty expected token never matches", !DictationServerHTTP.authorized("Bearer ", token: ""))
    }

    // MARK: Forms

    static func form(_ parts: [(name: String, filename: String?, content: Data)]) -> Data {
        var body = Data()
        for part in parts {
            var disposition = "Content-Disposition: form-data; name=\"\(part.name)\""
            if let filename = part.filename { disposition += "; filename=\"\(filename)\"" }
            body += Data("--\(boundary)\r\n\(disposition)\r\nContent-Type: application/octet-stream\r\n\r\n".utf8)
            body += part.content + Data("\r\n".utf8)
        }
        return body + Data("--\(boundary)--\r\n".utf8)
    }

    static let audio = Data([0x52, 0x49, 0x46, 0x46, 0x0D, 0x0A, 0x2D, 0x2D, 0x00, 0xFF])

    static func upload(_ parts: [(name: String, filename: String?, content: Data)])
        -> Result<DictationServerUpload, DictationServerResponse>
    {
        DictationServerUpload.parse(form(parts), boundary: boundary)
    }

    static func parsesForms() {
        let full = upload([("model", nil, Data("whisper-1".utf8)), ("file", "Clip.M4A", audio),
                           ("language", nil, Data("PL".utf8)), ("response_format", nil, Data("text".utf8))])
        check("a full form parses with binary audio intact",
              full == .success(DictationServerUpload(audio: audio, fileExtension: "m4a", language: .polish, format: .text)))
        check("defaults are json and the user's language",
              upload([("file", "clip", audio)])
                == .success(.init(audio: audio, fileExtension: nil, language: nil, format: .json)))
        check("no file is 400", (try? upload([("model", nil, Data("x".utf8))]).get()) == nil)
        check("an empty file is 400", (try? upload([("file", "a.wav", Data())]).get()) == nil)
        check("an unknown extension is 400", (try? upload([("file", "a.exe", audio)]).get()) == nil)
        check("an unknown language is 400",
              (try? upload([("file", "a.wav", audio), ("language", nil, Data("xx".utf8))]).get()) == nil)
        check("verbose_json is 400",
              (try? upload([("file", "a.wav", audio), ("response_format", nil, Data("srt".utf8))]).get()) == nil)
        let big = Data(repeating: 1, count: DictationServerHTTP.maximumFileBytes + 1)
        check("a file over 25 MB is 413", upload([("file", "a.wav", big)]) == .failure(.tooLarge))
        check("a body without the closing boundary is 400",
              (try? DictationServerUpload.parse(form([("file", "a.wav", audio)]).dropLast(10), boundary: boundary).get()) == nil)
        check("a body under another boundary is 400",
              (try? DictationServerUpload.parse(form([("file", "a.wav", audio)]), boundary: "other").get()) == nil)
    }

    static func readsInChunks() {
        let body = form([("file", "a.wav", audio)])
        let fields = goodFields.map { $0.hasPrefix("Content-Length") ? "Content-Length: \(body.count)" : $0 }
        let bytes = head(["POST \(DictationServerHTTP.transcriptionsPath) HTTP/1.1"] + fields) + body
        var reader = DictationServerReader(token: token, port: port)
        var steps: [DictationServerReader.Step] = []
        for index in bytes.indices { steps.append(reader.feed(bytes[index...index])) }
        check("one byte at a time reads to the form", steps.last == .form(body: body, boundary: boundary))
        check("nothing is decided before the last byte", steps.dropLast().allSatisfy { $0 == .more })

        var continued = DictationServerReader(token: token, port: port)
        let expecting = head(["POST \(DictationServerHTTP.transcriptionsPath) HTTP/1.1"] + fields + ["Expect: 100-continue"])
        check("Expect: 100-continue asks for the interim reply", continued.feed(expecting) == .sendContinue)
        check("then it wants exactly the body", continued.wanted == body.count)
        check("the body after it completes the form", continued.feed(body) == .form(body: body, boundary: boundary))

        var refused = DictationServerReader(token: "other", port: port)
        let early = refused.feed(head(["POST \(DictationServerHTTP.transcriptionsPath) HTTP/1.1"] + fields))
        check("a wrong token is answered from the head alone", early == .respond(.unauthorized))

        var models = DictationServerReader(token: token, port: port)
        let list = head(["GET \(DictationServerHTTP.modelsPath) HTTP/1.1"] + goodFields.prefix(2))
        check("models is answered from the head", models.feed(list) == .models)
    }

    static func encodesResponses() {
        let busy = String(decoding: DictationServerResponse.busy.encoded, as: UTF8.self)
        check("busy is 503 with Retry-After", busy.hasPrefix("HTTP/1.1 503 ") && busy.contains("\r\nRetry-After: 5\r\n"))
        let denied = String(decoding: DictationServerResponse.unauthorized.encoded, as: UTF8.self)
        check("401 names the scheme", denied.contains("\r\nWWW-Authenticate: Bearer\r\n"))
        check("401 never echoes the token", !denied.contains(token))
        let json = DictationServerResponse.transcript("Cześć \"x\"", format: .json)
        check("json is the OpenAI shape",
              (try? JSONSerialization.jsonObject(with: json.body)) as? [String: String] == ["text": "Cześć \"x\""])
        let text = DictationServerResponse.transcript("hi", format: .text)
        check("text is plain", text.body == Data("hi".utf8) && text.contentType.hasPrefix("text/plain"))
        let encoded = String(decoding: text.encoded, as: UTF8.self)
        check("length and close are declared", encoded.contains("Content-Length: 2\r\n") && encoded.contains("Connection: close"))
        let models = (try? JSONSerialization.jsonObject(with: DictationServerResponse.models(["parakeet-redux"]).body))
            as? [String: Any]
        check("models lists the id", ((models?["data"] as? [[String: Any]])?.first?["id"] as? String) == "parakeet-redux")
    }

    static func makesTokens() {
        var first = CountingGenerator()
        var second = CountingGenerator()
        let token = DictationServerHTTP.makeToken(using: &first)
        check("a token is 64 hex digits", token.count == 64 && token.allSatisfy(\.isHexDigit))
        check("the same stream gives the same token", token == DictationServerHTTP.makeToken(using: &second))
        check("the next one differs", token != DictationServerHTTP.makeToken(using: &first))
    }

    // MARK: Scheduling

    /// Lets started tasks reach their suspension points before the test looks.
    static func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    static func queueWaitsForUser() async {
        let queue = DictationServerQueue(capacity: 4)
        queue.setUserDictating(true)
        let log = Log()
        let waiter = Task {
            try await queue.enter()
            log.admitted = true
        }
        await settle()
        check("a request during the user's dictation waits", !log.admitted && queue.waitingCount == 1)
        queue.setUserDictating(false)
        await settle()
        check("it runs once the user is done", log.admitted && queue.isHeld)
        _ = await waiter.result
        queue.leave()
        check("leaving frees the model", !queue.isHeld)
    }

    static func queueRunsInOrder() async {
        let queue = DictationServerQueue(capacity: 4)
        try? await queue.enter()
        let log = Log()
        for number in 1...3 {
            Task {
                try await queue.enter()
                log.order.append(number)
            }
            await settle()
        }
        check("others wait behind the holder", log.order.isEmpty && queue.waitingCount == 3)
        for _ in 1...3 {
            queue.leave()
            await settle()
        }
        check("they run in arrival order, one at a time", log.order == [1, 2, 3])
        queue.leave()
    }

    static func queueRefusesWhenFull() async {
        let queue = DictationServerQueue(capacity: 1)
        try? await queue.enter()
        let first = Task { try await queue.enter() }
        await settle()
        let second = await Task { () -> Bool in
            do { try await queue.enter() } catch is DictationServerQueue.Full { return true } catch {}
            return false
        }.value
        check("a full queue refuses at once", second)
        queue.leave()
        _ = await first.result
        queue.leave()
    }

    static func queueDropsCancelledWaiter() async {
        let queue = DictationServerQueue(capacity: 4)
        queue.setUserDictating(true)
        let waiter = Task { try await queue.enter() }
        await settle()
        waiter.cancel()
        await settle()
        let cancelled: Bool
        if case .failure(let error) = await waiter.result { cancelled = error is CancellationError } else { cancelled = false }
        check("a cancelled waiter leaves with CancellationError", cancelled)
        check("and no longer waits", queue.waitingCount == 0)
        queue.setUserDictating(false)
        check("and never takes the model", !queue.isHeld)
    }

    /// As the server runs it: wait the user's turn out, then go through the add-on runner.
    static func userWinsRunningRequest() async {
        let fake = FakeDictation()
        fake.holds = true
        let runner = NotchcastTranscriptionRunner(dictation: fake)
        let queue = DictationServerQueue(capacity: 4)
        let request = Task { () -> Result<String, any Error> in
            try? await queue.enter()
            defer { queue.leave() }
            do {
                return .success(try await runner.transcribe(URL(fileURLWithPath: "/clip.wav")))
            } catch {
                return .failure(error)
            }
        }
        await settle()
        check("the request reached the model", fake.calls.count == 1)
        let user = Task { await fake.userDictates() }
        await settle()
        fake.release()
        let userGotModel = await user.value
        let outcome = await request.value
        check("the user's dictation gets the model", userGotModel)
        if case .failure(let error) = outcome {
            check("the request is answered busy", (error as? NotchcastTranscribeError) == .busy)
        } else {
            check("the request is answered busy", false)
        }
    }

    static func passesLanguage() async {
        let fake = FakeDictation()
        fake.result = .success("tekst")
        let runner = NotchcastTranscriptionRunner(dictation: fake)
        _ = try? await runner.transcribe(URL(fileURLWithPath: "/a.wav"), language: DictationLanguage.polish.rawValue)
        _ = try? await runner.transcribe(URL(fileURLWithPath: "/b.wav"))
        check("a request's language reaches Dictation, and nil keeps the user's", fake.languages == ["Polish", nil])
    }
}
