// notchcast-sources: Tinycast/Features/DictationExtras/Model/*.swift Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Settings/Model/SettingsFileKey.swift

import Foundation

func check(_ condition: Bool, _ message: String) {
    guard condition else { fatalError("nc-DictationExtras-cleanup-test: \(message)") }
}

/// Waits until cancelled, never on the clock, so the race is decided only by the other side.
func never() async {
    let stream = AsyncStream<Never> { _ in }
    for await _ in stream {}
}

struct Option: Equatable {
    let source: DictationCleanupModelPolicy.Source
    let id: String
}

func automatic(_ options: [Option]) -> Option? {
    DictationCleanupModelPolicy.automatic(from: options, source: \.source, id: \.id)
}

struct Boom: Error {}

@main
enum DictationExtrasCleanupTests {
    static func main() async {
        // Prompt: a blank custom prompt falls back; the transcript is delimited as data.
        let standard = DictationCleanupPrompt.standard
        check(DictationCleanupPrompt.instructions(custom: nil) == standard, "nil uses the default")
        check(DictationCleanupPrompt.instructions(custom: "  \n") == standard, "blank uses the default")
        check(DictationCleanupPrompt.instructions(custom: "Be terse.") == "Be terse.", "custom wins")
        check(standard.localizedCaseInsensitiveContains("translate"), "the default forbids translation")
        check(DictationCleanupPrompt.message(for: "hi") == "Transcript:\nhi", "the message frames the text")

        // Runner: the answer, trimmed, wins the race.
        let fired: @Sendable () async throws -> Void = {}
        let waits: @Sendable () async throws -> Void = {
            await never()
            try Task.checkCancellation()
        }
        var outcome = await DictationCleanupRunner.run("raw", generate: { " Clean. \n" }, deadline: waits)
        check(outcome == .cleaned("Clean."), "a trimmed answer is pasted, got \(outcome)")
        outcome = await DictationCleanupRunner.run("raw", generate: { " \n" }, deadline: waits)
        check(outcome == .failed(.empty), "an empty answer fails, got \(outcome)")
        outcome = await DictationCleanupRunner.run("raw", generate: { throw Boom() }, deadline: waits)
        check(outcome == .failed(.error), "a thrown error fails, got \(outcome)")

        // The deadline firing first is a timeout, and the slow model is cancelled.
        let slow: @Sendable () async throws -> String = {
            await never()
            try Task.checkCancellation()
            return "late"
        }
        outcome = await DictationCleanupRunner.run("raw", generate: slow, deadline: fired)
        check(outcome == .failed(.timeout), "a deadline first times out, got \(outcome)")
        check(DictationCleanupRunner.timeout == .seconds(10), "cleanup gets ten seconds")

        // Nothing to clean, or nothing to clean with: raw text, no notice.
        outcome = await DictationCleanupRunner.run("raw", generate: nil, deadline: fired)
        check(outcome == .skipped, "no model skips, got \(outcome)")
        outcome = await DictationCleanupRunner.run(" \n", generate: { "x" }, deadline: fired)
        check(outcome == .skipped, "a blank transcript skips, got \(outcome)")

        // Escape cancels the session: the failed call reports nothing.
        let session = Task { await DictationCleanupRunner.run("raw", generate: slow, deadline: waits) }
        session.cancel()
        outcome = await session.value
        check(outcome == .skipped, "a cancelled session skips, got \(outcome)")

        // Model policy: Claude before Codex, each one's lightest model first.
        let sonnet = Option(source: .claude, id: "claude-sonnet")
        let haiku = Option(source: .claude, id: "claude-Haiku")
        let codex = Option(source: .codex, id: "gpt-5")
        let codexMini = Option(source: .codex, id: "gpt-5-mini")
        let api = Option(source: .other, id: "gpt-5-mini")
        check(automatic([codexMini, sonnet, haiku]) == haiku, "Claude's lightest model first")
        check(automatic([codex, sonnet]) == sonnet, "any Claude beats Codex")
        check(automatic([api, codex, codexMini]) == codexMini, "Codex's lightest model without Claude")
        check(automatic([api, codex]) == codex, "Codex's first model when none is light")
        check(automatic([api]) == nil, "an API key is never picked on its own")
        check(automatic([]) == nil, "nothing installed picks nothing")

        // Gate: the transcript leaves only on a shortcut finish, with the switch on, outside a field.
        func sends(_ switchOn: Bool, _ cleansUp: Bool, _ hasField: Bool, _ liveTextEmpty: Bool) -> Bool {
            DictationCleanupPolicy.sends(
                switchOn: switchOn, cleansUp: cleansUp, hasField: hasField, liveTextEmpty: liveTextEmpty)
        }
        check(sends(true, true, false, true), "a shortcut finish with the switch on cleans up")
        check(!sends(false, true, false, true), "the switch off sends nothing")
        check(!sends(true, false, false, true), "Return sends nothing")
        check(!sends(true, true, true, true), "a composer mic sends nothing")
        check(!sends(true, true, false, false), "live insertion sends nothing")

        // A settings.json key would let a file send transcripts, delete history or rewrite the prompt.
        for path in ["dictation.cleansUp", "dictation.keepsHistory", "dictation.cleanupPrompt"] {
            check(SettingsFileKey(rawValue: path) == nil, "\(path) has no settings.json key")
        }

        // First model: an empty profile starts on Ultra; a stored choice is never overwritten.
        check(DictationFirstModel.seed(stored: nil) == "ultra", "nothing stored seeds Ultra")
        for stored in ["redux", "ultra", "qwen-0.6b", "qwen-1.7b"] {
            check(DictationFirstModel.seed(stored: stored) == nil, "a stored \(stored) stays")
        }

        print("nc-DictationExtras-cleanup-test: all passed")
    }
}
