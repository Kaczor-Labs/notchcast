# Taildrop

A Notchcast add-on (`Tinycast/Features/Notchcast/Taildrop/`, switch `taildrop`, off by default, Settings › Downloads). While it is on, the launcher lists one command per device Tailscale can send files to, `Taildrop to <device>`; running one sends the files and folders selected in Finder to that device through the local `tailscale` CLI. Receiving and auto-accept on the other device are out of scope.

## Invariants

- **The local CLI is the only door to Tailscale.** The add-on runs `tailscale file cp --targets` to list devices, `tailscale status --json` only to say why a listing failed, and `tailscale file cp <file> <address>:` to send. It opens no network connection of its own, stores no device list, and needs no entitlement or secret. The CLI is looked for inside `Tailscale.app` first, since that one matches the running app, then at the two Homebrew paths.
- **Commands follow the device list, and the list is read again each time the launcher opens.** The module publishes its commands through `context.setCommands`; a device's command id is built from its name alone (`command:nc-taildrop-to-<name in kebab case>`), so an alias or hotkey bound to a device survives every refresh; Settings has no rows to bind one yet (#1170). Two devices whose names give the same id: the first listed wins. An unchanged list publishes nothing.
- **No CLI, no commands.** With Tailscale not installed the add-on lists nothing. Installed but not running, signed out, or with no device able to receive, one command `Taildrop` stays so the reason has a place to be read: running it names the reason in the island and lists again.
- **A device's address reaches the CLI only as an IP literal.** `TaildropTarget.parse` drops any listing line whose first field is not made of hex digits, dots and colons, so nothing printed by the CLI can become an option of the next call.
- **A folder always travels as a zip.** `tailscale file cp` refuses a directory, so every selected folder (an app bundle included) is zipped with `/usr/bin/ditto` into a fresh folder under the temporary directory, sent, and that folder is deleted when the send ends, whether it finished, failed or was cancelled. Files go as they are. Two folders with one name get `Name.zip` and `Name 2.zip`.
- **One send at a time, one island notice.** Every state is the same notice (id `taildrop`): `Sending to <device>` with unknown progress until the selection is read and for a single item, otherwise `Sending <count> items to <device>` with the share of items already sent, then `Sent`, `Cancelled`, or the failure and its reason. A second command run during a send does nothing. Both island forms draw it through the island's own notice surface; the add-on has no view.
- **A click on the progress notice cancels a running send; no key does.** The island tells an add-on neither that it is open nor that the pointer is over it, so Esc could only be watched everywhere, and it would then cancel a send while the user works in another app. The add-on subscribes no tap and needs no Accessibility grant. Cancelling terminates the running tool.
- **Decisions live in `Model/`, facts come in through `TaildropSystem`.** Listing parsing, the failure mapping, the folder-or-file plan and the send sequence import Foundation only and take the CLI path, the tool runner, the Finder selection, the disk checks and the scratch folder as injected closures. `Tests/nc-Taildrop-module-test.swift` runs them and the module with a fake world: no real CLI, Finder, disk, network or clock. `Tests/nc-Taildrop-process-test.swift` runs the shipped tool runner against system tools.

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

Read through the core's `NotchcastAppleEvents.finderSelection` ([addons.md](addons.md) §2): Apple Events to Finder, one for `selection` and then one per selected item for its `URL`, 5 s each, off the main actor. The first use asks for the Automation grant for Finder; a refusal (`NotchcastAppleEvents.refused`) is its own failure state. No Finder, no selection or a timeout all read as nothing selected. Only local file URLs pass.
