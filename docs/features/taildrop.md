# Taildrop

A Notchcast add-on (`Tinycast/Features/Notchcast/Taildrop/`, switch `taildrop`, off by default, in Settings › Downloads under Files & Downloads). While it is on, the launcher has one command per device that can take a Taildrop, named `Taildrop to <device>`. Running one sends the files and folders selected in Finder to that device through the user's own `tailscale` command-line tool. Receiving, and accepting on the other device, are not part of it.

## Invariants

- **The device list is `tailscale file cp --targets`, never built here.** That call already means "this user's devices that can receive files, without this Mac", and prints the short host name. `TaildropTarget.parse` reads address, name and an optional status column per line and drops anything else. The list is read when the switch turns on and each time the launcher opens (`context.handleLauncherOpen`), with a 5 s limit.
- **A command is keyed by the device's Tailscale address, not its name.** The id is `command:nc-taildrop-<address>`, so a renamed device keeps its alias, hotkey and "Show in launcher" checkbox, and the send goes to the address (`<address>:`, IPv6 in brackets), which a name with odd characters cannot break.
- **Device names never enter the repository.** They exist only at run time and in this Mac's preferences (`taildropTargets` in the `.notchcast` suite, the last list, so the commands are there before `tailscale` answers and stay while it is stopped). Fixtures use invented names.
- **A missing CLI hides the commands; a silent one keeps them.** No `tailscale` found: no commands, and the saved list is dropped. Found but stopped, signed out or slow: the last list stays, so running a command can say why it fails.
- **Every file goes in on stdin** (`tailscale file cp --name=<file name> - <address>:`), one run per file, in selection order. The CLI of Tailscale's Mac app is sandboxed and cannot open a path it is given, and stdin works for every install.
- **A folder always goes as a zip.** `tailscale file cp` refuses a directory ("directories not supported"), so a folder (a package too) is zipped with `/usr/bin/ditto -c -k --sequesterRsrc --keepParent` into its own new folder under the temporary directory, sent as `<folder>.zip`, and that folder is deleted when the send ends: sent, failed or cancelled.
- **One send at a time.** A second command while one runs posts "A Taildrop is already running." on its own notice and leaves the first alone.
- **Decisions live in `Model/`** (target parsing, zip or send, the order of runs, reading a failure), with Finder, the disk and every program behind `TaildropEnvironment`. `Service/` holds the module, the process runner and the live environment.

## What the island shows

One notice, id `taildrop`, through `context.presenter`: "Sending to <device>" with a progress ring (no share while a folder is zipped, then bytes sent over all bytes), then "Sent to <device>", or a failure notice with the reason. The progress is ended before the result is posted, so the result opens below a notch like any other message. No island page is added.

Progress is real: `TaildropProcess` gives the file to the program as its stdin and reads the shared file offset four times a second, which is how far the program has read.

Cancel: a click on the island while it shows the progress, or Esc. Esc is heard through the shared event tap, subscribed only while a send runs and never swallowed, so the front app still gets the key; it needs Accessibility access, and without it only the click cancels. A cancelled send posts "Taildrop cancelled".

## Failures

| Case | Notice |
| - | - |
| Nothing selected in Finder | Select files or folders in Finder first. |
| Automation access to Finder refused | Allow Automation access to read the Finder selection. |
| Finder gave no answer in 5 s | Finder did not respond in time. |
| No `tailscale` found when the command runs | Tailscale is not installed. |
| The CLI cannot reach Tailscale | Tailscale is not running. |
| Signed out, or connected to no tailnet | Tailscale is signed out or disconnected. |
| A selected item is gone or unreadable | Could not read <name>. |
| `ditto` failed or left no archive | Could not zip <name>. |
| Anything else `tailscale` reports | Its own last line, cut at 120 characters, else "Taildrop failed." |

`TaildropFailure(output:)` tells the two Tailscale states apart by the CLI's text ("not connected to the tailnet" or "logged out"; "failed to connect to local tailscale" or "not running"), checked against Tailscale 1.104's strings. The CLI reports signed out and disconnected with the same words, so they share one notice.

`tailscale` is looked for in `/opt/homebrew/bin`, `/usr/local/bin`, each `PATH` folder, then `/Applications/Tailscale.app/Contents/MacOS/Tailscale`.

## Tests

- `Tests/nc-Taildrop-model-test.swift`: target parsing from fixture output, failure reading, the listing call, zip or send, order, cleanup after success, failure and cancel, with a fake runner (`Tests/TaildropFixture.swift`): no `tailscale`, no network, no clock.
- `Tests/nc-Taildrop-module-test.swift`: the add-on as the controller starts it: off by default, device commands, the launcher-open refresh, the saved list, one progress notice, each failure notice, busy, Esc, click and switch-off mid-send.
- `Tests/nc-Taildrop-process-test.swift`: the shipped runner, disk reads and `ditto` against a stand-in `tailscale` shell script: a file arrives whole on stdin, a folder arrives as a zip with the folder as its root, the temporary archive is deleted, a cancelled run ends its program.

Not verified: a real transfer between two devices, the sandboxed Mac app CLI taking a file on stdin, the Finder Apple Events, and the island on a real display.
