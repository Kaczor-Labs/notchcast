# Taildrop

A Notchcast add-on (`Tinycast/Features/Notchcast/Taildrop/`, switch `taildrop`, off by default, Settings › Downloads). While it is on, the launcher lists one command per device Tailscale can send files to, `Taildrop to <device>`; running one sends the files and folders selected in Finder to that device through the local `tailscale` CLI. Receiving and auto-accept on the other device are out of scope.

## Invariants

- **The local CLI is the only door to Tailscale.** The add-on runs `tailscale file cp --targets` to list devices, `tailscale status --json` only to say why a listing failed, and `tailscale file cp <file> <address>:` to send. It opens no network connection of its own, stores no device list, and needs no entitlement or secret. The CLI is looked for at the two Homebrew paths, then inside `Tailscale.app`.
- **Commands follow the device list, and the list is read again each time the launcher opens.** The module publishes its commands through `context.setCommands`; a device's command id is built from its name alone (`command:nc-taildrop-to-<name in kebab case>`), so an alias or hotkey bound to a device survives every refresh. Two devices whose names give the same id: the first listed wins. An unchanged list publishes nothing.
- **No CLI, no commands.** With Tailscale not installed the add-on lists nothing. Installed but not running, signed out, or with no device able to receive, one command `Taildrop` stays so the reason has a place to be read: running it names the reason in the island and lists again.
- **A device's address reaches the CLI only as an IP literal.** `TaildropTarget.parse` drops any listing line whose first field is not made of hex digits, dots and colons, so nothing printed by the CLI can become an option of the next call.
- **A folder always travels as a zip.** `tailscale file cp` refuses a directory, so every selected folder (an app bundle included) is zipped with `/usr/bin/ditto` into a fresh folder under the temporary directory, sent, and that folder is deleted when the send ends, whether it finished, failed or was cancelled. Files go as they are. Two folders with one name get `Name.zip` and `Name 2.zip`.
- **One send at a time, one island notice.** Every state is the same notice (id `taildrop`): `Sending to <device>` with progress (unknown for a single item, otherwise the share of items already sent), then `Sent`, `Cancelled`, or the failure and its reason. A second command run during a send does nothing. Both island forms draw it through the island's own notice surface; the add-on has no view.
- **Esc cancels a running send, and is watched only while one runs.** The add-on subscribes an observing key tap when a send starts and removes it when the send ends; Esc with a modifier held is left alone. A click on the progress notice cancels too. Cancelling terminates the running tool. Without the Accessibility grant the tap is not live, and the click is the way to cancel.
- **Decisions live in `Model/`, facts come in through `TaildropSystem`.** Listing parsing, the failure mapping, the folder-or-file plan and the send sequence import Foundation only and take the CLI path, the tool runner, the Finder selection, the disk checks and the scratch folder as injected closures. `Tests/nc-Taildrop-module-test.swift` runs them and the module with a fake world: no real CLI, Finder, disk, network or clock.

## Failure states

Each is one island notice marked as a failure; none stops the app.

| State | Notice |
| - | - |
| Nothing selected in Finder, or every selected item is gone | Select files in Finder first. |
| Finder Automation refused | Allow Automation access to read the Finder selection. |
| Tailscale not running | Tailscale is not running. |
| Tailscale signed out | Tailscale is signed out. |
| No device can receive files | No device can receive files. |
| The device left the list since the launcher opened | That device no longer receives files. |
| The device is offline | `<device>` is offline. |
| A folder could not be zipped | Could not zip `<folder>`. |
| The CLI refused the send | Taildrop failed: `<the CLI's last error line>` |

Why a listing failed is read from `BackendState` in `tailscale status --json`, never from the CLI's prose: `NeedsLogin` and `NeedsMachineAuth` are signed out, `Running` keeps the CLI's own last error line, anything else (or no answer) is not running. After a failed send the device list is read again.

## The Finder selection

Read with two Apple Events to Finder (`selection`, then each item's `URL`), 5 s each, off the main actor. The first use asks for the Automation grant for Finder; a refusal is its own failure state. No Finder, no selection or a timeout all read as nothing selected. Only local file URLs pass.
