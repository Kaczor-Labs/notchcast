// notchcast-sources: Tinycast/Features/DictationSharing/Service/DictationServerListener.swift
// notchcast-sources: Tinycast/Features/DictationSharing/Model/DictationServerClients.swift
// notchcast-sources: Tinycast/Features/DictationSharing/Model/DictationServerHTTP.swift
// notchcast-sources: Tinycast/Features/DictationSharing/Model/DictationServerUpload.swift
// notchcast-sources: Tinycast/Features/Dictation/Model/DictationLanguage.swift
import Darwin
import Foundation
import Network

/// Starts the endpoint's listener as `DictationServer` does: only IPv4 loopback reaches it.
@main
@MainActor
struct DictationBindTest {
    static var failures = 0
    static var checks = 0
    nonisolated static let reply = Data(repeating: 0x61, count: 300_000)

    static func check(_ label: String, _ ok: Bool) {
        checks += 1
        if !ok {
            failures += 1
            print("FAIL \(label)")
        }
    }

    static func main() async {
        guard let (port, serving) = try? await listen({ connection, _ in
            await DictationServerListener.reply(connection) { reply }
        }) else {
            print("FAILED could not create the listener")
            exit(1)
        }
        check("the listener starts on a port the kernel picks", port != nil)
        if let port {
            check("127.0.0.1 connects", connect(ipv4("127.0.0.1", port: port)) == 0)
            check("::1 is refused", connect(ipv6("::1", port: port)) == ECONNREFUSED)
            if let address = networkAddress() {
                check("the Mac's network address \(address) does not connect", connect(ipv4(address, port: port)) != 0)
            } else {
                print("note: no non-loopback IPv4 address, so the off-loopback refusal is not checked")
            }
            let request = Data("POST /v1/audio/transcriptions HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n".utf8)
            let received = await roundTrip(port: port, request: request, halfClosed: false)
            check("an open client gets the whole reply", received == reply)
        }
        serving.cancel()
        _ = await serving.value
        async let complete: Void = checkHalfClose(complete: true)
        async let truncated: Void = checkHalfClose(complete: false)
        async let reset: Void = checkReset(afterHalfClose: false)
        async let resetAfterFIN: Void = checkReset(afterHalfClose: true)
        _ = await (complete, truncated, reset, resetAfterFIN)
        print(failures == 0 ? "PASS DictationBindTest (\(checks) checks)" : "FAILED \(failures)/\(checks)")
        if failures > 0 { exit(1) }
    }

    static let token = String(repeating: "ab", count: 32)
    static let body = Data([
        "--clip", "Content-Disposition: form-data; name=\"file\"; filename=\"clip.wav\"", "", "RIFF0000WAVE", "--clip--", "",
    ].joined(separator: "\r\n").utf8)
    nonisolated static let transcript = DictationServerResponse.transcript("hello", format: .text).encoded

    static func upload(port: UInt16, complete: Bool = true) -> Data {
        let fields = [
            "POST /v1/audio/transcriptions HTTP/1.1", "Host: 127.0.0.1:\(port)", "Authorization: Bearer \(token)",
            "Content-Type: multipart/form-data; boundary=clip", "Content-Length: \(body.count)", "", "",
        ]
        return Data(fields.joined(separator: "\r\n").utf8) + (complete ? body : body.dropLast())
    }

    static func listen(
        _ serve: @escaping @MainActor @Sendable (NetworkConnection<TCP>, UInt16) async -> Void
    ) async throws -> (UInt16?, Task<Void, Never>) {
        let listener = try DictationServerListener.make(port: .any)
        let (ports, ready) = AsyncStream<UInt16>.makeStream()
        let task = Task {
            defer { ready.finish() }
            try? await listener.onStateUpdate { listener, state in
                switch state {
                case .ready:
                    if let port = listener.port { ready.yield(port.rawValue) }
                    ready.finish()
                case .waiting, .failed, .cancelled: ready.finish()
                default: break
                }
            }.run { connection in
                if let port = listener.port {
                    await serve(connection, port.rawValue)
                }
            }
        }
        var next = ports.makeAsyncIterator()
        return (await next.next(), task)
    }

    static func checkHalfClose(complete: Bool) async {
        let (work, transcribing) = AsyncStream<Void>.makeStream()
        guard let (port, serving) = try? await listen({ connection, port in
            defer { transcribing.finish() }
            let reader = DictationServerReader(token: token, port: Int(port))
            let request = try? await DictationServerListener.readRequest(connection, reader: reader) {}
            guard case .form(let received, "clip") = request, received == body
            else { return }
            guard let eof = try? await connection.receive(atLeast: 1, atMost: 1), eof.metadata.endOfStream else { return }
            await DictationServerListener.reply(connection) {
                transcribing.yield(())
                return await transcribe(received)
            }
        }), let port else {
            check("the half-close fixture listens", false)
            return
        }
        let request = upload(port: port, complete: complete)
        let response = await roundTrip(port: port, request: request, halfClosed: true)
        serving.cancel()
        await serving.value
        transcribing.finish()
        var next = work.makeAsyncIterator()
        let transcribed = await next.next() != nil
        let expected = complete ? transcript : Data()
        let ok = response == expected && transcribed == complete
        check(complete ? "a half-closed upload gets the whole 200 transcript before EOF (\(response?.count ?? -1) bytes)"
              : "a half-closed incomplete body gets no reply or transcription", ok)
    }

    @concurrent
    nonisolated static func transcribe(_ bytes: Data) async -> Data {
        guard case .success = DictationServerUpload.parse(bytes, boundary: "clip") else { return Data() }
        return transcript
    }

    static func checkReset(afterHalfClose: Bool) async {
        let (started, transcribing) = AsyncStream<Void>.makeStream()
        let (hold, release) = AsyncStream<Void>.makeStream()
        let (results, cancelled) = AsyncStream<Bool>.makeStream()
        guard let (port, serving) = try? await listen({ connection, port in
            defer {
                transcribing.finish()
                cancelled.finish()
            }
            let reader = DictationServerReader(token: token, port: Int(port))
            let request = try? await DictationServerListener.readRequest(connection, reader: reader) {}
            guard case .form = request else { return }
            if afterHalfClose {
                guard let eof = try? await connection.receive(atLeast: 1, atMost: 1), eof.metadata.endOfStream else { return }
            }
            await DictationServerListener.reply(connection) {
                transcribing.yield(())
                for await _ in hold {}
                cancelled.yield(Task.isCancelled)
                return transcript
            }
        }), let port else {
            check("the reset fixture listens", false)
            return
        }
        guard let descriptor = socketToListener(port) else {
            check("the reset client connects", false)
            serving.cancel()
            await serving.value
            return
        }
        var abort = linger(l_onoff: 1, l_linger: 0)
        let resets = setsockopt(descriptor, SOL_SOCKET, SO_LINGER, &abort, socklen_t(MemoryLayout<linger>.size)) == 0
        let bytes = upload(port: port)
        let wrote = bytes.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) == $0.count }
        var start = started.makeAsyncIterator()
        let halfClosed = !afterHalfClose || shutdown(descriptor, SHUT_WR) == 0
        let began = if resets && wrote && halfClosed { await start.next() != nil } else { false }
        close(descriptor)
        check("the reset follows the start of transcription", began)
        if began {
            var result = results.makeAsyncIterator()
            let label = afterHalfClose ? "a TCP reset after half-close" : "a TCP reset"
            check("\(label) cancels in-flight transcription", await result.next() == true)
        }
        release.finish()
        serving.cancel()
        await serving.value
    }

    /// Blocking reads stay off the cooperative pool, which CI's strict mode cuts to one thread.
    nonisolated static func roundTrip(port: UInt16, request: Data, halfClosed: Bool) async -> Data? {
        await withCheckedContinuation { done in
            DispatchQueue.global().async {
                done.resume(returning: blockingRoundTrip(port: port, request: request, halfClosed: halfClosed))
            }
        }
    }

    nonisolated static func blockingRoundTrip(port: UInt16, request: Data, halfClosed: Bool) -> Data? {
        guard let descriptor = socketToListener(port) else { return nil }
        defer { close(descriptor) }
        let wrote = request.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) == $0.count }
        guard wrote, !halfClosed || shutdown(descriptor, SHUT_WR) == 0 else { return nil }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            if count < 0 { return nil }
            if count == 0 { return data }
            data.append(contentsOf: buffer.prefix(count))
        }
    }

    nonisolated static func socketToListener(_ port: UInt16) -> Int32? {
        var (address, length) = ipv4("127.0.0.1", port: port)
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }
        var one: Int32 = 1
        var cap = timeval(tv_sec: 5, tv_usec: 0)
        _ = setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        _ = setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &cap, socklen_t(MemoryLayout<timeval>.size))
        let connected = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(descriptor, $0, length) }
        }
        guard connected == 0 else {
            close(descriptor)
            return nil
        }
        return descriptor

    }

    nonisolated static func ipv4(_ text: String, port: UInt16) -> (sockaddr_storage, socklen_t) {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        _ = inet_pton(AF_INET, text, &address.sin_addr)
        return (storage(address), socklen_t(MemoryLayout<sockaddr_in>.size))
    }

    nonisolated static func ipv6(_ text: String, port: UInt16) -> (sockaddr_storage, socklen_t) {
        var address = sockaddr_in6()
        address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        address.sin6_family = sa_family_t(AF_INET6)
        address.sin6_port = port.bigEndian
        _ = inet_pton(AF_INET6, text, &address.sin6_addr)
        return (storage(address), socklen_t(MemoryLayout<sockaddr_in6>.size))
    }

    nonisolated static func storage(_ address: some Any) -> sockaddr_storage {
        var storage = sockaddr_storage()
        withUnsafeMutableBytes(of: &storage) { target in withUnsafeBytes(of: address) { target.copyMemory(from: $0) } }
        return storage
    }

    /// 0 when it connects, else the errno; the 2 s cap only stops a hang.
    nonisolated static func connect(_ target: (sockaddr_storage, socklen_t)) -> Int32 {
        var (address, length) = target
        let descriptor = socket(Int32(address.ss_family), SOCK_STREAM, 0)
        guard descriptor >= 0 else { return errno }
        defer { close(descriptor) }
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        let result = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(descriptor, $0, length) }
        }
        if result == 0 { return 0 }
        guard errno == EINPROGRESS else { return errno }
        var waiting = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
        guard poll(&waiting, 1, 2_000) == 1 else { return ETIMEDOUT }
        var failure: Int32 = 0
        var size = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &failure, &size) == 0 else { return errno }
        return failure
    }

    /// The first IPv4 address of an interface that is up and not loopback.
    nonisolated static func networkAddress() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(bitPattern: entry.pointee.ifa_flags)
            guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == sa_family_t(AF_INET),
                flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0
            else { continue }
            var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var inet = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            guard inet_ntop(AF_INET, &inet, &text, socklen_t(text.count)) != nil else { continue }
            return String(decoding: text.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
        return nil
    }
}
