// notchcast-sources: Tinycast/Features/Notchcast/Agents/Model/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Notchcast/Agents/Service/AgentCLIConversation.swift
// notchcast-sources: Tinycast/Features/Notchcast/Agents/Service/AgentFeedStore.swift
// notchcast-sources: Tinycast/Features/Notchcast/Agents/Service/ClaudeUsageReader.swift
// notchcast-sources: Tinycast/Features/Notchcast/Agents/Service/CodexUsageReader.swift
// notchcast-sources: Tinycast/Platform/ExecutableLocator.swift Tinycast/Platform/ProcessExit.swift

import Foundation

func check(_ condition: Bool, _ message: @autoclosure () -> String) {
    if !condition { fatalError(message()) }
}

let now = Date(timeIntervalSince1970: 1_795_111_200)  // 2026-11-19 18:00 UTC
let clock: @Sendable () -> Date = { now }

/// Each answer is one line, as the CLI writes it.
let usage = #"{"rate_limits_available":true,"rate_limits":{"five_hour":null,"#
    + #""seven_day":{"utilization":90,"resets_at":"2026-11-23T01:59:59.825376+00:00"},"#
    + #""model_scoped":[{"display_name":"Fable","utilization":78,"resets_at":"2026-11-23T01:59:59.825518+00:00"}]}}"#
let codexLimits = #"{"rateLimitsByLimitId":{"codex":{"limitId":"codex","#
    + #""primary":{"usedPercent":100,"windowDurationMins":10080,"resetsAt":1795260977}}},"#
    + #""rateLimitResetCredits":{"availableCount":0,"credits":[]}}"#

/// A scratch folder per case, so the cases share nothing.
func scratch() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "nc-agents-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// A stand-in CLI: records its arguments and environment, then answers each line `answers` matches.
func fakeCLI(in folder: URL, named name: String, answers: [(match: String, reply: [String])]) throws -> URL {
    var script = "#!/bin/sh\nprintf '%s\\n' \"$@\" > '\(folder.path)/args'\nenv > '\(folder.path)/env'\n"
    script += "while IFS= read -r line; do\n  case \"$line\" in\n"
    for (match, reply) in answers {
        script += "    *'\(match)'*) " + reply.map { "printf '%s\\n' '\($0)'; " }.joined() + ";;\n"
    }
    script += "  esac\ndone\n"
    let url = folder.appending(path: name)
    try script.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
}

func recorded(_ folder: URL, _ file: String) -> [String] {
    let text = (try? String(contentsOf: folder.appending(path: file), encoding: .utf8)) ?? ""
    return text.split(separator: "\n", omittingEmptySubsequences: false).dropLast().map(String.init)
}

func control(_ id: String, _ response: String) -> String {
    #"{"type":"control_response","response":{"subtype":"success","request_id":"\#(id)","response":\#(response)}}"#
}

func claudeAnswers(usage answer: String) -> [(match: String, reply: [String])] {
    [(#""subtype":"initialize""#, [#"{"type":"system","subtype":"init"}"#, control("initialize", "{}")]),
     (#""subtype":"get_usage""#, [control("other", "{}"), answer])]
}

func claudeReader(_ folder: URL, cli: URL?, directory: String = "", timeout: Duration = .seconds(10)) -> ClaudeUsageReader {
    let base = ["PATH": "/usr/bin:/bin", "CLAUDE_CODE_ENTRYPOINT": "cli", "ANTHROPIC_API_KEY": "secret",
                "CLAUDE_CONFIG_DIR": "/elsewhere", "CLAUDECODE": "1", "HOME": folder.path]
    return ClaudeUsageReader(
        name: "C1", launch: ClaudeLaunch(directory: directory), home: folder, timeout: timeout, environment: base,
        now: clock, locate: { cli })
}

func claudeDefaultAccount() async throws {
    let folder = try scratch()
    let cli = try fakeCLI(in: folder, named: "claude", answers: claudeAnswers(usage: control("usage", usage)))
    let account = try await claudeReader(folder, cli: cli).read()
    check(account.state == .ok && account.checkedAt == now, "read: \(account)")
    check(account.windows.map(\.usedPercent) == [90, 78] && account.windows[1].scope == "Fable", "\(account.windows)")
    let args = recorded(folder, "args")
    check(args == ClaudeLaunch.arguments, "a check runs no tool, hook or MCP server: \(args)")
    let env = recorded(folder, "env")
    check(env.contains("DISABLE_AUTOUPDATER=1") && env.contains("NO_COLOR=1"), "never updates itself: \(env)")
    check(!env.contains { $0.hasPrefix("ANTHROPIC_") || $0.hasPrefix("CLAUDE_") || $0.hasPrefix("CLAUDECODE") },
          "the app's own Claude sign-in never reaches the default account: \(env)")
    print("claude, default account: ok")
}

func claudeChosenFolder() async throws {
    let folder = try scratch()
    let config = folder.appending(path: ".claude-work")
    try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
    let fetched = Int(now.addingTimeInterval(-10).timeIntervalSince1970 * 1000)
    try Data(#"{"cachedUsageUtilization":{"fetchedAtMs":\#(fetched)}}"#.utf8).write(to: config.appending(path: ".claude.json"))
    try Data(#"{"env":{"HTTPS_PROXY":"http://proxy:8080"}}"#.utf8).write(to: config.appending(path: "settings.json"))
    let cli = try fakeCLI(in: folder, named: "claude", answers: claudeAnswers(usage: control("usage", usage)))
    let account = try await claudeReader(folder, cli: cli, directory: config.path).read()
    check(account.state == .ok && account.checkedAt == now.addingTimeInterval(-10), "observed when fetched: \(account)")
    let env = recorded(folder, "env")
    check(env.contains("CLAUDE_CONFIG_DIR=\(config.path)") && env.contains("HTTPS_PROXY=http://proxy:8080"),
          "the chosen folder and its proxy: \(env)")

    let old = Int(now.addingTimeInterval(-5 * 60).timeIntervalSince1970 * 1000)
    try Data(#"{"cachedUsageUtilization":{"fetchedAtMs":\#(old)}}"#.utf8).write(to: config.appending(path: ".claude.json"))
    let reused = try await claudeReader(folder, cli: cli, directory: config.path).read()
    check(reused.state == .unavailable && reused.windows.isEmpty, "a saved copy is no reading of the account")

    let gone = try scratch()
    let unused = try fakeCLI(in: gone, named: "claude", answers: [])
    let missing = try await claudeReader(gone, cli: unused, directory: gone.appending(path: "nope").path).read()
    check(missing.state == .signedOut && recorded(gone, "args").isEmpty, "a missing folder never falls back, never starts")
    print("claude, chosen folder: ok")
}

func claudeFailures() async throws {
    let folder = try scratch()
    let signedOut = try fakeCLI(in: folder, named: "claude", answers: claudeAnswers(
        usage: control("usage", #"{"rate_limits_available":false,"rate_limits":null}"#)))
    check(try await claudeReader(folder, cli: signedOut).read().state == .signedOut, "signed out")

    let refusal = #"{"type":"control_response","response":{"subtype":"error","request_id":"usage","#
        + #""error":"Unsupported control request subtype: get_usage"}}"#
    let old = try fakeCLI(in: try scratch(), named: "claude", answers: claudeAnswers(usage: refusal))
    check(try await claudeReader(folder, cli: old).read().state == .outdated, "too old for the request")

    check(try await claudeReader(folder, cli: nil).read().state == .missing, "not installed")

    let quits = try scratch().appending(path: "claude")
    try "#!/bin/sh\nexit 0\n".write(to: quits, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: quits.path)
    check(try await claudeReader(folder, cli: quits).read().state == .unavailable, "an exit without an answer")
    let notExecutable = try scratch().appending(path: "claude")
    try "nothing".write(to: notExecutable, atomically: true, encoding: .utf8)
    check(try await claudeReader(folder, cli: notExecutable).read().state == .unavailable, "a CLI that cannot start")

    check(ClaudeUsageReader.state(forError: "Please run /login") == .signedOut, "a sign-in error")
    check(ClaudeUsageReader.state(forError: "Rate limited") == .unavailable, "anything else")
    print("claude failures: ok")
}

/// A stand-in that ignores SIGTERM and never answers; it names its process first.
func stubbornCLI(in folder: URL) throws -> URL {
    let url = folder.appending(path: "claude")
    try "#!/bin/sh\necho $$ > '\(folder.path)/pid'\ntrap '' TERM\nexec /bin/sleep 30\n"
        .write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
}

func pid(in folder: URL) -> pid_t? {
    (try? String(contentsOf: folder.appending(path: "pid"), encoding: .utf8))
        .flatMap { pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
}

func isGone(_ pid: pid_t) -> Bool { kill(pid, 0) == -1 && errno == ESRCH }

/// Watches a real process from outside, so it waits on real time; `cap` bounds each wait.
func eventually(within cap: Duration = .seconds(3), _ condition: () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let until = clock.now + cap
    while !condition() {
        guard clock.now < until else { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}

func conversationEnds() async throws {
    let folder = try scratch()
    let silent = try fakeCLI(in: folder, named: "claude", answers: [])
    // The deadline is a real timer inside the conversation; 300 ms caps this one wait.
    let late = try await claudeReader(folder, cli: silent, timeout: .milliseconds(300)).read()
    check(late.state == .unavailable, "a CLI that never answers costs the deadline: \(late)")

    let clock = ContinuousClock()
    let deaf = try scratch()
    var started = clock.now
    let held = try await claudeReader(deaf, cli: try stubbornCLI(in: deaf), timeout: .milliseconds(300)).read()
    check(held.state == .unavailable && clock.now - started < .seconds(2),
          "the deadline holds against a CLI that ignores SIGTERM: \(clock.now - started)")
    guard let deafPID = pid(in: deaf) else { fatalError("the stand-in never started") }
    check(await eventually { isGone(deafPID) }, "and it is killed")

    let cancelled = try scratch()
    let cli = try stubbornCLI(in: cancelled)
    let reading = Task { try await claudeReader(cancelled, cli: cli).read() }
    check(await eventually { pid(in: cancelled) != nil }, "the stand-in starts")
    started = clock.now
    reading.cancel()
    do {
        _ = try await reading.value
        check(false, "a cancelled read returns no account")
    } catch is CancellationError {}
    check(clock.now - started < .seconds(2), "cancelling returns without waiting on the child: \(clock.now - started)")
    check(await eventually { isGone(pid(in: cancelled)!) }, "and the child is killed")
    print("conversation ends: ok")
}

func codexAnswers(account: String, limits: String) -> [(match: String, reply: [String])] {
    [(#""initialize""#, [#"{"id":1,"result":{"userAgent":"codex"}}"#]),
     (#""account/read""#, [#"{"method":"account/updated","params":{}}"#, #"{"id":99,"result":{}}"#,
                           #"{"id":2,"result":\#(account)}"#]),
     (#""account/rateLimits/read""#, [limits])]
}

func codexReader(_ cli: URL?) -> CodexUsageReader {
    CodexUsageReader(environment: ["PATH": "/usr/bin:/bin"], version: "1.0", now: clock, locate: { cli })
}

func codex() async throws {
    let folder = try scratch()
    let cli = try fakeCLI(in: folder, named: "codex", answers: codexAnswers(
        account: #"{"account":{"type":"chatgpt","planType":"prolite"}}"#, limits: #"{"id":3,"result":\#(codexLimits)}"#))
    let account = try await codexReader(cli).read()
    check(account.name == "Codex" && account.provider == "codex" && account.state == .ok, "read: \(account)")
    check(account.windows == [AgentWindow(
        kind: .weekly, usedPercent: 100, resetsAt: Date(timeIntervalSince1970: 1_795_260_977), durationMinutes: 10_080)],
        "\(account.windows)")
    check(recorded(folder, "args") == ["-c", "features.plugins=false", "app-server"], "the app server, no plugins")

    let apiKey = try fakeCLI(in: try scratch(), named: "codex", answers: codexAnswers(
        account: #"{"account":{"type":"apiKey"}}"#, limits: ""))
    check(try await codexReader(apiKey).read().state == .signedOut, "an API key has no plan")
    let old = try fakeCLI(in: try scratch(), named: "codex", answers: codexAnswers(
        account: #"{"account":{"type":"chatgpt"}}"#, limits: #"{"id":3,"error":{"code":-32601,"message":"nope"}}"#))
    check(try await codexReader(old).read().state == .outdated, "a Codex without the method")
    check(try await codexReader(nil).read().state == .missing, "not installed")
    check(CodexUsageReader.state(forError: ["message": "Not logged in"]) == .signedOut, "signed out by words")
    check(CodexUsageReader.state(forError: ["message": "unknown variant `x`"]) == .outdated, "unknown variant")
    check(CodexUsageReader.state(forError: nil) == .unavailable, "no error at all")
    print("codex: ok")
}

func feedStore() throws {
    let folder = try scratch().appending(path: "feed")
    let store = AgentFeedStore(folder: folder)
    check(store.read() == .missing, "no folder yet: this Mac only")
    let local = AgentFeed(generatedAt: now, machines: [AgentMachine(name: "MBA", accounts: [
        AgentAccount(name: "C1", provider: "claude", checkedAt: now, state: .ok,
                     windows: [AgentWindow(kind: .weekly, usedPercent: 45, durationMinutes: 10_080)])])])
    try store.writeLocal(local)
    check(try AgentFeed.decode(Data(contentsOf: store.localURL)) == local, "local.json holds this Mac's readings")
    check(store.read() == .missing, "local.json is never read as the feed")
    let text = try String(contentsOf: store.localURL, encoding: .utf8)
    check(!text.contains("@") && text.contains(#""version" : 1"#), "versioned, nothing but names and numbers")

    try local.encoded().write(to: store.feedURL)
    check(store.read() == .loaded(local), "the feed")
    try Data(#"{"version":2,"anything":true}"#.utf8).write(to: store.feedURL)
    check(store.read() == .unknownVersion(2), "a newer feed is refused, not guessed")
    try Data("{".utf8).write(to: store.feedURL)
    check(store.read() == .unreadable, "a broken feed")
    try FileManager.default.removeItem(at: store.feedURL)
    try FileManager.default.createDirectory(at: store.feedURL, withIntermediateDirectories: false)
    check(store.read() == .unreadable, "a folder in the feed's place")
    print("feed store: ok")
}

@main
enum AgentsModuleTest {
    @MainActor
    static func main() async throws {
        try await claudeDefaultAccount()
        try await claudeChosenFolder()
        try await claudeFailures()
        try await conversationEnds()
        try await codex()
        try feedStore()
        print("nc-Agents-module-test: ok")
    }
}
