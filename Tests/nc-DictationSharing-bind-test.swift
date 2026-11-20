// notchcast-sources: Tinycast/Features/DictationSharing/Service/DictationServerListener.swift
// notchcast-sources: Tinycast/Features/DictationSharing/Model/DictationServerClients.swift
import Darwin
import Foundation
import Network

/// Starts the endpoint's listener as `DictationServer` does: only IPv4 loopback reaches it.
@main
@MainActor
struct DictationBindTest {
    static var failures = 0
    static var checks = 0
    static var ready: CheckedContinuation<UInt16?, Never>?
    nonisolated static let reply = Data(repeating: 0x61, count: 300_000)

    static func check(_ label: String, _ ok: Bool) {
        checks += 1
        if !ok {
            failures += 1
            print("FAIL \(label)")
        }
    }

    static func main() async {
        guard let listener = try? DictationServerListener.make(port: .any) else {
            print("FAILED could not create the listener")
            exit(1)
        }
        let serving = Task {
            try? await listener.onStateUpdate { listener, state in
                switch state {
                case .ready: started(listener.port?.rawValue)
                case .waiting, .failed: started(nil)
                default: break
                }
            }.run { connection in
                await DictationServerListener.reply(connection) { reply }
            }
        }
        let deadline = Task {
            guard (try? await Task.sleep(for: .seconds(5))) != nil else { return }
            started(nil)
        }
        let port = await withCheckedContinuation { ready = $0 }
        deadline.cancel()
        check("the listener starts on a port the kernel picks", port != nil)
        if let port {
            check("127.0.0.1 connects", connect(ipv4("127.0.0.1", port: port)) == 0)
            check("::1 is refused", connect(ipv6("::1", port: port)) == ECONNREFUSED)
            if let address = networkAddress() {
                check("the Mac's network address \(address) does not connect", connect(ipv4(address, port: port)) != 0)
            } else {
                print("note: no non-loopback IPv4 address, so the off-loopback refusal is not checked")
            }
            let received = await roundTrip(port: port)
            check("a request gets the whole reply (\(received) of \(reply.count) bytes)", received == reply.count)
        }
        serving.cancel()
        _ = await serving.value
        print(failures == 0 ? "PASS DictationBindTest (\(checks) checks)" : "FAILED \(failures)/\(checks)")
        if failures > 0 { exit(1) }
    }

    static func started(_ port: UInt16?) {
        ready?.resume(returning: port)
        ready = nil
    }

    /// Off the main actor, where the reply's work runs; bytes read before EOF, a 5 s cap per read.
    @concurrent
    nonisolated static func roundTrip(port: UInt16) async -> Int {
        var (address, length) = ipv4("127.0.0.1", port: port)
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return -1 }
        defer { close(descriptor) }
        var cap = timeval(tv_sec: 5, tv_usec: 0)
        _ = setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &cap, socklen_t(MemoryLayout<timeval>.size))
        let connected = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(descriptor, $0, length) }
        }
        guard connected == 0 else { return -1 }
        let request = Array("POST /v1/audio/transcriptions HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n".utf8)
        guard write(descriptor, request, request.count) == request.count else { return -1 }
        var total = 0
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            guard count > 0 else { return total }
            total += count
        }
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
            return String(cString: text)
        }
        return nil
    }
}
