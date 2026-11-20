// notchcast-sources: Tinycast/Features/DictationSharing/Service/DictationServerListener.swift
import Darwin
import Foundation
import Network

/// Starts the endpoint's listener as `DictationServer` does and proves only IPv4 loopback reaches it.
@main
@MainActor
struct DictationBindTest {
    static var failures = 0
    static var checks = 0
    static var ready: CheckedContinuation<Bool, Never>?

    static func check(_ label: String, _ ok: Bool) {
        checks += 1
        if !ok {
            failures += 1
            print("FAIL \(label)")
        }
    }

    static func main() async {
        guard let port = freePort(), let endpointPort = NWEndpoint.Port(rawValue: port),
            let listener = try? DictationServerListener.make(port: endpointPort)
        else {
            print("FAILED could not create the listener")
            exit(1)
        }
        let serving = Task {
            try? await listener.onStateUpdate { _, state in
                switch state {
                case .ready: started(true)
                case .waiting, .failed: started(false)
                default: break
                }
            }.run { _ in }
        }
        let isReady = await withCheckedContinuation { ready = $0 }
        check("the listener starts on a free port", isReady)
        if isReady {
            check("127.0.0.1 connects", connect(ipv4("127.0.0.1", port: port)) == 0)
            check("::1 is refused", connect(ipv6("::1", port: port)) == ECONNREFUSED)
            if let address = networkAddress() {
                check("the Mac's network address \(address) is refused", connect(ipv4(address, port: port)) == ECONNREFUSED)
            } else {
                print("note: no non-loopback IPv4 address, so the off-loopback refusal is not checked")
            }
        }
        serving.cancel()
        _ = await serving.value
        print(failures == 0 ? "PASS DictationBindTest (\(checks) checks)" : "FAILED \(failures)/\(checks)")
        if failures > 0 { exit(1) }
    }

    static func started(_ isReady: Bool) {
        ready?.resume(returning: isReady)
        ready = nil
    }

    /// A port the kernel just handed out on 127.0.0.1, released for the listener to take.
    static func freePort() -> UInt16? {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var (address, length) = ipv4("127.0.0.1", port: 0)
        let bound = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, length) }
        }
        let named = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
        }
        guard bound == 0, named == 0 else { return nil }
        let port = withUnsafeBytes(of: address) { $0.load(as: sockaddr_in.self).sin_port }
        return UInt16(bigEndian: port)
    }

    static func ipv4(_ text: String, port: UInt16) -> (sockaddr_storage, socklen_t) {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        _ = inet_pton(AF_INET, text, &address.sin_addr)
        return (storage(address), socklen_t(MemoryLayout<sockaddr_in>.size))
    }

    static func ipv6(_ text: String, port: UInt16) -> (sockaddr_storage, socklen_t) {
        var address = sockaddr_in6()
        address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        address.sin6_family = sa_family_t(AF_INET6)
        address.sin6_port = port.bigEndian
        _ = inet_pton(AF_INET6, text, &address.sin6_addr)
        return (storage(address), socklen_t(MemoryLayout<sockaddr_in6>.size))
    }

    static func storage(_ address: some Any) -> sockaddr_storage {
        var storage = sockaddr_storage()
        withUnsafeMutableBytes(of: &storage) { target in withUnsafeBytes(of: address) { target.copyMemory(from: $0) } }
        return storage
    }

    /// 0 when it connects, else the errno; a refusal answers at once, so the 2 s cap only stops a hang.
    static func connect(_ target: (sockaddr_storage, socklen_t)) -> Int32 {
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
    static func networkAddress() -> String? {
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
