import Darwin
import Foundation

/// One Claude account through Claude Code's `get_usage` request: no model, tool or hook runs, no token is read.
struct ClaudeUsageReader: Sendable {
    var name: String
    var launch: ClaudeLaunch
    var home: URL = FileManager.default.homeDirectoryForCurrentUser
    var timeout: Duration = .seconds(25)
    var environment: [String: String] = ProcessInfo.processInfo.environment
    var now: @Sendable () -> Date = { Date() }
    var locate: @Sendable () async -> URL? = { await ExecutableLocator.locate("claude") }

    private enum Failure: Error {
        case state(AgentAccountState)
    }

    @concurrent func read() async throws -> AgentAccount {
        let result = await attempt()
        try Task.checkCancellation()
        switch result {
        case .success(let account): return account
        case .failure(.state(let state)): return AgentAccount(name: name, provider: "claude", checkedAt: now(), state: state)
        }
    }

    private func attempt() async -> Result<AgentAccount, Failure> {
        guard isAvailable() else { return .failure(.state(.signedOut)) }
        guard let executable = await locate() else { return .failure(.state(.missing)) }
        let started = now()
        let before = ClaudeLaunch.Profile(try? Data(contentsOf: launch.profileURL(home: home)))
        let settings = try? Data(contentsOf: launch.configurationURL(home: home).appending(path: "settings.json"))
        let environment = ExecutableLocator.environment(
            running: executable, inherited: launch.environment(environment, settings: settings))
        let answer = await AgentCLIConversation.run(
            executable, arguments: ClaudeLaunch.arguments, environment: environment, timeout: timeout
        ) { conversation -> Result<Data, Failure> in
            if case .failure(let failure) = await ask(conversation, id: "initialize", request: ["subtype": "initialize"]) {
                return .failure(failure)
            }
            return await ask(conversation, id: "usage", request: ["subtype": "get_usage", "skip_behaviors": true])
        }
        guard let answer else { return .failure(.state(.unavailable)) }
        return answer.flatMap { data in
            guard let usage = try? ClaudeUsageAnswer.decode(data) else { return .failure(.state(.unavailable)) }
            guard usage.signedIn else { return .failure(.state(.signedOut)) }
            // Read once Claude Code has exited, so what it fetched for this answer is on disk.
            let after = ClaudeLaunch.Profile(try? Data(contentsOf: launch.profileURL(home: home)))
            guard before.identity == after.identity, isAvailable() else { return .failure(.state(.unavailable)) }
            // A copy saved before this check began was answered in place of the account, which was not reached.
            if let fetched = after.usageFetched, started.timeIntervalSince(fetched) > ClaudeLaunch.reuse {
                return .failure(.state(.unavailable))
            }
            let observed = min(now(), after.usageFetched ?? now())
            guard let account = usage.account(name: name, observed: observed) else {
                return .failure(.state(.unavailable))
            }
            return .success(account)
        }
    }

    private func ask(_ conversation: AgentCLIConversation, id: String, request: [String: Any]) async
        -> Result<Data, Failure>
    {
        guard conversation.send(["type": "control_request", "request_id": id, "request": request]) else {
            return .failure(.state(.unavailable))
        }
        while let message = await conversation.next() {
            guard message["type"] as? String == "control_response",
                let response = message["response"] as? [String: Any], response["request_id"] as? String == id
            else { continue }
            guard response["subtype"] as? String == "success" else {
                return .failure(.state(Self.state(forError: response["error"] as? String ?? "")))
            }
            let payload = response["response"] as? [String: Any] ?? [:]
            guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
                return .failure(.state(.unavailable))
            }
            return .success(data)
        }
        return .failure(.state(.unavailable))
    }

    /// A Claude Code from before the request answers "Unsupported control request subtype".
    static func state(forError error: String) -> AgentAccountState {
        let error = error.lowercased()
        if error.contains("supported") || error.contains("unknown") { return .outdated }
        if error.contains("auth") || error.contains("login") || error.contains("sign in") { return .signedOut }
        return .unavailable
    }

    /// Never falls back to the default account when a chosen folder is gone; only metadata is looked at.
    func isAvailable() -> Bool {
        guard !launch.isDefault else { return true }
        let directory = launch.directory
        guard directory.hasPrefix("/"), directory.utf8.count <= 4_096 else { return false }
        let folder = launch.configurationURL(home: home)
        let manager = FileManager.default
        guard folder.path != "/", folder.resolvingSymlinksInPath() != home.resolvingSymlinksInPath(),
            let metadata = try? manager.attributesOfItem(atPath: folder.path),
            metadata[.type] as? FileAttributeType == .typeDirectory,
            (metadata[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
            let permissions = metadata[.posixPermissions] as? NSNumber, permissions.intValue & 0o022 == 0,
            let profile = try? manager.attributesOfItem(atPath: launch.profileURL(home: home).path),
            profile[.type] as? FileAttributeType == .typeRegular,
            (profile[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
            (profile[.referenceCount] as? NSNumber)?.intValue == 1
        else { return false }
        return true
    }
}
