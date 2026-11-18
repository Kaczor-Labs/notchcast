// notchcast-sources: Tinycast/Features/Notchcast/ScriptCommands/Model/*.swift
import Foundation

let home = "/tmp/me"
let executables: Set<String> = ["/tmp/me/bin/update.sh", "/tmp/me/My Scripts/it's.sh"]
let folders: Set<String> = [home, "/tmp/me/Code", "/tmp"]

func environment(shell: String? = "/bin/zsh") -> ScriptInvocation.Environment {
    ScriptInvocation.Environment(
        shell: shell, home: home, isExecutableFile: { executables.contains($0) }, isDirectory: { folders.contains($0) })
}

func invocation(_ row: ScriptCommand, shell: String? = "/bin/zsh") -> ScriptInvocation? {
    try? ScriptInvocation.make(for: row, in: environment(shell: shell)).get()
}

func report(_ outcome: ScriptOutcome, _ output: String = "", minutes: Int = 30) -> ScriptReport {
    ScriptReport(name: "Update packages", result: ScriptRun.Result(outcome: outcome, output: output), timeoutMinutes: minutes)
}

@main
enum ScriptCommandsModelTests {
    static func main() {
        // Acceptance 1's row: a one-line command through the login shell, in the home folder.
        let update = ScriptCommand(id: "a1", name: " Update packages ", script: "brew update && brew upgrade")
        let built = invocation(update)
        precondition(built?.shell == "/bin/zsh", "the user's shell runs it")
        precondition(built?.arguments == ["-lc", "brew update && brew upgrade"], "login shell, command verbatim")
        precondition(built?.folder == home, "no folder runs in home")
        precondition(built?.timeout == .seconds(30 * 60), "30 minutes by default")
        precondition(update.title == "Update packages" && update.slug == "run-a1", "trimmed name, frozen slug shape")
        precondition(update.isRunnable, "a name and a script make a command")

        precondition(invocation(update, shell: "/opt/homebrew/bin/fish")?.shell == "/opt/homebrew/bin/fish", "$SHELL")
        for shell in [nil, "", "fish"] {
            precondition(invocation(update, shell: shell)?.shell == "/bin/zsh", "no usable $SHELL falls back to zsh")
        }

        // A path to an executable is run as one word, never split or expanded by the shell.
        let script = ScriptCommand(id: "b", name: "Mine", script: "~/bin/update.sh", folder: "~/Code")
        precondition(invocation(script)?.arguments == ["-lc", "exec '/tmp/me/bin/update.sh'"], "executable path")
        precondition(invocation(script)?.folder == "/tmp/me/Code", "a ~ folder expands")
        let quoted = ScriptCommand(id: "c", name: "Q", script: "/tmp/me/My Scripts/it's.sh")
        precondition(invocation(quoted)?.arguments == ["-lc", #"exec '/tmp/me/My Scripts/it'\''s.sh'"#],
                     "spaces and quotes stay inside one word")
        let notExecutable = ScriptCommand(id: "d", name: "D", script: "/tmp/me/notes.txt")
        precondition(invocation(notExecutable)?.arguments == ["-lc", "/tmp/me/notes.txt"], "anything else is a command")

        // Failures that stop a run before it starts.
        let gone = ScriptCommand(id: "e", name: "E", script: "make", folder: "~/Gone")
        precondition((try? ScriptInvocation.make(for: gone, in: environment()).get()) == nil, "a missing folder fails")
        if case .failure(let failure) = ScriptInvocation.make(for: gone, in: environment()) {
            precondition(failure == .missingFolder("~/Gone"), "names the folder as typed")
        }
        let empty = ScriptCommand(id: "f", name: "F", script: "   ")
        if case .failure(let failure) = ScriptInvocation.make(for: empty, in: environment()) {
            precondition(failure == .noScript, "an empty script fails")
        } else {
            preconditionFailure("an empty script never runs")
        }
        precondition(!empty.isRunnable && !ScriptCommand(id: "g", script: "ls").isRunnable, "no script or no name")

        // Timeouts: clamped so a typo can neither disable it nor stop a run at once.
        precondition(ScriptCommand(id: "h", timeoutMinutes: 0).timeout == .seconds(60), "at least a minute")
        precondition(ScriptCommand(id: "h", timeoutMinutes: 99_999).clampedTimeoutMinutes == 1440, "at most a day")

        // Stored rows.
        let stored = Data(#"[{"id":"x","name":"A","script":"ls"},{"id":"x","name":"B"},{"id":"y"}]"#.utf8)
        let rows = ScriptCommand.decodeList(stored)
        precondition(rows.map(\.id) == ["x", "y"], "a duplicated id keeps its first row")
        precondition(rows[0].timeoutMinutes == 30 && rows[0].folder.isEmpty, "absent fields take their defaults")
        precondition(ScriptCommand.decodeList(Data("nope".utf8)).isEmpty && ScriptCommand.decodeList(nil).isEmpty,
                     "unreadable data is no rows")
        let saved = [update, script, ScriptCommand(id: "z", timeoutMinutes: 5)]
        precondition(ScriptCommand.decodeList(ScriptCommand.encodeList(saved)) == saved, "rows round-trip")

        // Result wording (the harness has no bundle, so each key's English is what shows).
        precondition(report(.exited(0), "==> Upgraded 3\n") == ScriptReport.expect("Update packages finished", false),
                     "success")
        precondition(report(.exited(1), "Updating\nError: No such keg\n\n")
            == ScriptReport.expect("Update packages failed (exit 1): Error: No such keg", true), "failure, last line")
        precondition(report(.exited(2)) == ScriptReport.expect("Update packages failed (exit 2)", true), "silent failure")
        precondition(report(.timedOut, "", minutes: 30) == ScriptReport.expect("Update packages stopped after 30 min", true),
                     "timeout")
        precondition(report(.couldNotStart("No such file")) ==
            ScriptReport.expect("Update packages could not start: No such file", true), "launch failure")
        let missing = ScriptReport(name: "E", failure: .missingFolder("~/Gone"))
        precondition(missing == ScriptReport.expect("E could not start: no folder at ~/Gone", true), "missing folder")

        precondition(ScriptReport.lastLine(of: "50%\r75%\r100%  \r") == "100%", "a carriage return ends a line")
        precondition(ScriptReport.lastLine(of: " \n\t\n") == nil, "blank output has no last line")
        let long = ScriptReport.lastLine(of: String(repeating: "x", count: 500))
        precondition(long?.count == ScriptReport.lastLineLimit && long?.hasSuffix("…") == true, "a long line is cut")

        print("PASS: script commands model covers building, timeouts, stored rows and result wording")
    }
}

extension ScriptReport {
    static func expect(_ text: String, _ isFailure: Bool) -> ScriptReport {
        var report = ScriptReport(name: "", failure: .noScript)
        report.text = text
        report.isFailure = isFailure
        return report
    }
}
