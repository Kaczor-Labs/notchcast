# System Tools

A Notchcast add-on (`Tinycast/Features/Notchcast/SystemTools/`) behind one switch, **System tools** in Settings › Notchcast › Mac Tweaks, off by default. While it is on it offers five launcher commands, **Kill Process**, **Test Network Quality**, **Copy Wi-Fi Password**, **Copy Local IP Address** and **Copy Public IP Address**, and a **Touch ID for sudo** switch under it.

## Invariants

- **Touch ID for sudo writes only `/etc/pam.d/sudo_local`**, which `/etc/pam.d/sudo` includes and macOS keeps across updates. `SudoTouchIDPolicy.change` is the only edit: a pure text transform that appends `auth sufficient pam_tid.so` or removes those lines, keeps every other line byte for byte, and returns nil when the file already says what was asked, so nothing is written and nothing prompts. The switch shows the file, read on appear and after every write, never a stored preference. An existing file that cannot be read is never rewritten.
- **One privileged route, asked every time.** `SudoTouchIDFiles.live` runs a fresh `/usr/bin/osascript` with `do shell script … with administrator privileges`, so macOS shows its own admin prompt for each change and no grant carries over. The new text travels as an argument, is staged root-owned and `0444` next to the target, then moved over it. No helper tool, no stored credential, no entitlement. A declined prompt (AppleScript `-128`) changes nothing and reports nothing.
- **Kill Process lists only the user's own processes**, never Notchcast (this copy or another), pid 1, `loginwindow`, `WindowServer`, `launchd` or `kernel_task`, by name or by path (`ProcessListPolicy.isProtected`). A signal first matches pid and start time again, so a pid the system handed on is left alone. Regular apps quit through `NSRunningApplication` (`terminate`, `forceTerminate`), other processes through `SIGTERM` and `SIGKILL`; a process already gone counts as quit. Nothing escalates to admin rights.
- **Kill Process and local addresses are adapted from Vorssaint** (GPL-3.0-or-later): `Model/ProcessListPolicy.swift`, `Model/NetworkAddressPolicy.swift`, `Service/LiveProcesses.swift` and `Service/LiveNetworkAddresses.swift` keep its notice and are listed in `notchcast/licenses/borrowed.md`.
- **Force Quit asks first**, through `DialogController` via `context.surfaces.confirm`; a context without surfaces answers no.
- **One network test at a time**, `/usr/bin/networkQuality -c`, its progress and result on the island as notices (`systemTools.network`), no new island page. Esc (an observing key tap that exists only while the test runs, live only with Accessibility) or a click on the progress notice cancels and ends the tool. Every run ends with a notice: the result, Network Test Failed, or Network Test Cancelled.
- **Copy Wi-Fi Password lists the saved networks** (`networksetup -listpreferredwirelessnetworks`), because macOS 26 hides the current network's name from an app without Location Services, and Notchcast asks for no location. The chosen network's password comes from `security find-generic-password -D "AirPort network password" -a <network> -w`, so macOS asks the user each time. The secret is read from the pipe only, never logged. It is copied concealed (`org.nspasteboard.ConcealedType`) so clipboard history skips it, and shown on the island for 8 s.
- **The public IP is the add-on's one request**, sent only when the command runs: `https://api.ipify.org` on a private `.ephemeral` session with `urlCache = nil`. A reply counts only when it is one bare IPv4 or IPv6 address. Local addresses come from the interface list (IPv4, up and running, no loopback, tunnels or peer links), labelled with the system's connection name.
- **Harnesses touch nothing real**: no process is read or signalled, no tool runs, and the pam files live in a scratch folder.

## How it works

| Piece | Does |
| - | - |
| `SystemToolsAddon` | The switch, both commands and the Touch ID row. |
| `Model/ProcessListPolicy` | Which processes are offered, CPU between two readings as a share of the whole Mac (0–100), memory as physical footprint, and the order: names containing the query or the pid it spells, busiest first, ties by pid. |
| `Model/NetworkAddressPolicy` | Which interfaces carry a local address, and their order. |
| `Model/NetworkInfoPolicy` | Reads `networksetup`'s Wi-Fi device and saved networks, and checks the public-IP reply. |
| `Model/SudoTouchIDPolicy` | The `sudo_local` transform and whether `sudo` still includes it. |
| `Model/NetworkQualityResult` | Parses `networkQuality -c` (`dl_throughput`, `ul_throughput`, `responsiveness`, `error_code`) into "↓ 278 Mbps  ↑ 21.4 Mbps  1,234 RPM". |
| `Service/LiveProcesses` | libproc readings of the user's processes and the quit itself. |
| `Service/KillProcessSession` | One open picker: readings, query, selection by pid, and the quit. |
| `Service/SystemToolsModule` | Opens the picker; runs, cancels and reports the network test. |
| `Service/SystemToolsModule+Addresses` | The address and Wi-Fi password commands: one lookup at a time, each answer shown and copied. |
| `Service/SystemToolsPicking` | What a picker lists and does; `WiFiNetworkSession` lists the saved networks. |
| `Service/SudoTouchIDStore` | Reads the pam files, writes through `SudoTouchIDFiles`, rereads. |
| `UI/SystemToolsPicker` | The stock `PopoverMenu` in a `MenuPanel`, centred on the pointer's display: typing filters, ↩ chooses (Kill Process: ↩ quits, ⌥↩ or ⌥-click force quits, refreshed every 2 s), Esc clears the query and then closes. |

Harnesses: `Tests/nc-SystemTools-policy-test.swift` (filtering and sorting, the pam transform, output parsing, interface rules and reply checks), `Tests/nc-SystemTools-module-test.swift` (the switch gating its commands, kill by name, Force Quit asking first, the network test's result, cancel and failure, the Touch ID store on scratch files) and `Tests/nc-SystemTools-network-test.swift` (local and public addresses, the Wi-Fi picker and password copy), sharing the fakes in `Tests/nc-SystemTools-fixture.swift`.
