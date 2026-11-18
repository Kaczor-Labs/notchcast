import Darwin
import Foundation
import Synchronization

/// One aria2c child answering JSON-RPC on a loopback port only it may own.
final class Aria2Session: TorrentSession {
    private let child: ChildProcess
    private let running: Task<Void, Never>
    private let exited: ExitFlag
    private let endpoint: URL
    private let secret: String
    private let http: URLSession

    private init(child: ChildProcess, running: Task<Void, Never>, exited: ExitFlag, port: Int, secret: String) {
        self.child = child
        self.running = running
        self.exited = exited
        endpoint = URL(string: "http://127.0.0.1:\(port)/jsonrpc")!
        self.secret = secret
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = 10
        http = URLSession(configuration: configuration)
    }

    /// Starts aria2c and returns once the listener on its port is proven to be that child.
    @concurrent
    static func start(tools: DownloadToolLookup, downloads: URL, state: URL, extra: [String]) async throws -> Aria2Session {
        guard let executable = tools.find(.aria2c) else { throw TorrentEngineMissing() }
        try FileManager.default.createDirectory(
            at: state, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: state.path)
        let port = try freePort()
        var generator = SystemRandomNumberGenerator()
        let secret = (0..<4).map { _ in String(format: "%016llx", generator.next() as UInt64) }.joined()
        let arguments = Aria2Arguments(port: port, secret: secret, stateDirectory: state, downloads: downloads,
                                       parent: getpid(), extra: extra)
        guard FileManager.default.createFile(
            atPath: arguments.configuration.path, contents: Data(arguments.configurationText.utf8),
            attributes: [.posixPermissions: 0o600])
        else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: arguments.configuration.path)
        let child = ChildProcess(executable: executable, arguments: arguments.arguments,
                                 environment: tools.environment, reaper: tools.children)
        let exited = ExitFlag()
        let running = Task.detached {
            _ = try? await child.run()
            exited.value.withLock { $0 = true }
        }
        let session = Aria2Session(child: child, running: running, exited: exited, port: port, secret: secret)
        do {
            try await session.waitUntilReady(port: port, tools: tools)
        } catch {
            await session.stop()
            throw error
        }
        return session
    }

    var isAlive: Bool { !exited.value.withLock { $0 } }

    func add(_ source: TorrentSource, options: [String: String]) async throws -> String {
        switch source {
        case .magnet(let link): try await call("aria2.addUri", [[link], options])
        case .torrent(let data): try await call("aria2.addTorrent", [data.base64EncodedString(), [String](), options])
        }
    }

    func status(_ gid: String) async throws -> TorrentStatus {
        try await call("aria2.tellStatus", [gid, [
            "status", "completedLength", "totalLength", "downloadSpeed", "connections", "numSeeders", "seeder",
            "errorMessage", "followedBy", "files", "bittorrent",
        ]])
    }

    func remove(_ gid: String) async {
        let _: String? = try? await call("aria2.forceRemove", [gid])
        let _: String? = try? await call("aria2.removeDownloadResult", [gid])
    }

    /// Interrupt so aria2c saves its DHT state, then terminate, then kill.
    func stop() async {
        if let pid = child.pid { kill(pid, SIGINT) }
        if await finished(within: .seconds(3)) { return }
        child.cancel()
        await running.value
    }

    private func finished(within limit: Duration) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: limit)
        while ContinuousClock.now < deadline {
            if exited.value.withLock({ $0 }) { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return exited.value.withLock { $0 }
    }

    private func waitUntilReady(port: Int, tools: DownloadToolLookup) async throws {
        let failed = String(localized: "aria2c could not start.", table: "NotchcastDownloads")
        for _ in 0..<100 {
            try Task.checkCancellation()
            guard !exited.value.withLock({ $0 }) else { throw Aria2Failure(message: failed) }
            if let pid = child.pid, try await Self.listeners(on: port, tools: tools) == [pid] {
                let _: Aria2Version = try await call("aria2.getVersion", [])
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw Aria2Failure(message: failed)
    }

    /// The pids `lsof` names as listening on the loopback port; anything but our child means stop.
    private static func listeners(on port: Int, tools: DownloadToolLookup) async throws -> Set<pid_t> {
        let result = try await ChildProcess(
            executable: URL(filePath: "/usr/sbin/lsof"),
            arguments: ["-nP", "-a", "-iTCP@127.0.0.1:\(port)", "-sTCP:LISTEN", "-Fp"],
            environment: tools.environment).run()
        let lines = result.output.split(separator: "\n")
        return Set(lines.compactMap { line -> pid_t? in line.hasPrefix("p") ? pid_t(String(line.dropFirst())) : nil })
    }

    private static func freePort() throws -> Int {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else { throw POSIXError(.EIO) }
        defer { close(socket) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socket, $0, length) == 0 && getsockname(socket, $0, &length) == 0
            }
        }
        guard bound else { throw POSIXError(.EADDRNOTAVAIL) }
        return Int(UInt16(bigEndian: address.sin_port))
    }

    private func call<Value: Decodable>(_ method: String, _ params: [Any]) async throws -> Value {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": "notchcast", "method": method, "params": ["token:" + secret] + params,
        ])
        let (data, _) = try await http.data(for: request)
        let reply = try JSONDecoder().decode(Aria2Reply<Value>.self, from: data)
        if let error = reply.error { throw Aria2Failure(message: error.message) }
        guard let result = reply.result else { throw Aria2Failure(message: method) }
        return result
    }
}

private final class ExitFlag: Sendable {
    let value = Mutex(false)
}

private struct Aria2Version: Decodable { let version: String }

private struct Aria2Reply<Value: Decodable>: Decodable {
    struct Failure: Decodable { let message: String }
    let result: Value?
    let error: Failure?
}
