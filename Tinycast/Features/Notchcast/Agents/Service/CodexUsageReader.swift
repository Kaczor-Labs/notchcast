import Foundation

/// The Codex account through Codex's own `app-server`, which signs in with credentials this never reads.
struct CodexUsageReader: Sendable {
    var name = "Codex"
    var timeout: Duration = .seconds(20)
    var environment: [String: String] = ProcessInfo.processInfo.environment
    var version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    var now: @Sendable () -> Date = { Date() }
    var locate: @Sendable () async -> URL? = { await ExecutableLocator.locate("codex") }

    @concurrent func read() async throws -> AgentAccount {
        let result = await attempt()
        try Task.checkCancellation()
        switch result {
        case .success(let account): return account
        case .failure(let failure):
            return AgentAccount(name: name, provider: "codex", checkedAt: now(), state: failure.state)
        }
    }

    private struct Failure: Error {
        var state: AgentAccountState
    }

    private func attempt() async -> Result<AgentAccount, Failure> {
        guard let executable = await locate() else { return .failure(Failure(state: .missing)) }
        let environment = ExecutableLocator.environment(running: executable, inherited: environment)
        let client: [String: Any] = ["name": "notchcast", "title": "Notchcast", "version": version]
        let answer = await AgentCLIConversation.run(
            executable, arguments: ["-c", "features.plugins=false", "app-server"], environment: environment,
            timeout: timeout
        ) { conversation -> Result<AgentAccount, Failure> in
            var lastID = 0
            func ask(_ method: String, _ params: [String: Any] = [:]) async -> Result<Data, Failure> {
                lastID += 1
                return await Self.ask(conversation, id: lastID, method: method, params: params)
            }
            if case .failure(let failure) = await ask("initialize", ["clientInfo": client, "capabilities": NSNull()]) {
                return .failure(failure)
            }
            guard conversation.send(["method": "initialized"]) else { return .failure(Failure(state: .unavailable)) }
            switch await ask("account/read") {
            case .failure(let failure): return .failure(failure)
            case .success(let data):
                guard (try? JSONDecoder().decode(CodexAccountAnswer.self, from: data))?.signedIn == true else {
                    return .failure(Failure(state: .signedOut))
                }
            }
            return await ask("account/rateLimits/read").flatMap { data in
                guard let account = (try? CodexUsageAnswer.decode(data))?.account(name: name, observed: now()) else {
                    return .failure(Failure(state: .unavailable))
                }
                return .success(account)
            }
        }
        return answer ?? .failure(Failure(state: .unavailable))
    }

    private static func ask(
        _ conversation: AgentCLIConversation, id: Int, method: String, params: [String: Any]
    ) async -> Result<Data, Failure> {
        guard conversation.send(["id": id, "method": method, "params": params]) else {
            return .failure(Failure(state: .unavailable))
        }
        while let message = await conversation.next() {
            // Notifications and the server's own requests are not the answer.
            guard message["method"] == nil, (message["id"] as? NSNumber)?.intValue == id else { continue }
            guard let result = message["result"] as? [String: Any],
                let data = try? JSONSerialization.data(withJSONObject: result)
            else { return .failure(Failure(state: state(forError: message["error"]))) }
            return .success(data)
        }
        return .failure(Failure(state: .unavailable))
    }

    /// The server words its refusals: a method it does not know is an unknown variant to it.
    static func state(forError error: Any?) -> AgentAccountState {
        let error = error as? [String: Any]
        let message = (error?["message"] as? String ?? "").lowercased()
        if (error?["code"] as? NSNumber)?.intValue == -32601 || message.contains("unknown variant")
            || message.contains("method not found") { return .outdated }
        if message.contains("authentication") || message.contains("not logged in") { return .signedOut }
        return .unavailable
    }
}
