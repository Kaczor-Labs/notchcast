# System Tools

A Notchcast add-on (`Tinycast/Features/Notchcast/SystemTools/`) behind one switch, **System tools** in Settings › Notchcast › Mac Tweaks, off by default. While it is on it offers two launcher commands, **Kill Process** and **Test Network Quality**, and a **Touch ID for sudo** switch under it.

## Invariants

- **Touch ID for sudo writes only `/etc/pam.d/sudo_local`**, which `/etc/pam.d/sudo` includes and macOS keeps across updates. `SudoTouchIDPolicy.change` is the only edit: a pure text transform that appends `auth sufficient pam_tid.so` or removes those lines, keeps every other line byte for byte, and returns nil when the file already says what was asked, so nothing is written and nothing prompts. The switch shows the file, read on appear and after every write, never a stored preference. An existing file that cannot be read is never rewritten.
- **One privileged route, asked every time.** `SudoTouchIDFiles.live` runs a fresh `/usr/bin/osascript` with `do shell script … with administrator privileges`, so macOS shows its own admin prompt for each change and no grant carries over. The new text travels as an argument, is staged root-owned and `0444` next to the target, then moved over it. No helper tool, no stored credential, no entitlement. A declined prompt (AppleScript `-128`) changes nothing and reports nothing.
- **Kill Process lists only the user's own processes**, never Notchcast itself, pid 1, `loginwindow`, `WindowServer`, `launchd` or `kernel_task` (`ProcessListPolicy.canStop`). A signal first matches pid and start time again, so a pid the system handed on is left alone. Apps quit through `NSRunningApplication` (`terminate`, `forceTerminate`), other processes through `SIGTERM` and `SIGKILL`.
- **Force Quit asks first**, through `DialogController` via `context.surfaces.confirm`; a context without surfaces answers no.
- **One network test at a time**, `/usr/bin/networkQuality -c`, its progress and result on the island as notices (`systemTools.network`), no new island page. Esc (an observing key tap that exists only while the test runs, live only with Accessibility) or a click on the progress notice cancels and ends the tool. Every run ends with a notice: the result, Network Test Failed, or Network Test Cancelled.
- **Harnesses touch nothing real**: no process is read or signalled, no tool runs, and the pam files live in a scratch folder.

## How it works

| Piece | Does |
| - | - |
| `SystemToolsAddon` | The switch, both commands and the Touch ID row. |
| `Model/ProcessListPolicy` | Which processes are offered, CPU between two readings (per core, like Activity Monitor), memory as physical footprint, and the order: names starting with the query, then names containing it, busiest first. |
| `Model/SudoTouchIDPolicy` | The `sudo_local` transform and whether `sudo` still includes it. |
| `Model/NetworkQualityResult` | Parses `networkQuality -c` (`dl_throughput`, `ul_throughput`, `responsiveness`, `error_code`) into "↓ 278 Mbps  ↑ 21.4 Mbps  1,234 RPM". |
| `Service/KillProcessSession` | One open picker: readings, query, selection by pid, and the quit. |
| `Service/SystemToolsModule` | Opens the picker; runs, cancels and reports the network test. |
| `Service/SudoTouchIDStore` | Reads the pam files, writes through `SudoTouchIDFiles`, rereads. |
| `UI/KillProcessPicker` | The stock `PopoverMenu` in a `MenuPanel`, centred on the pointer's display, refreshed every 2 s: typing filters, ↩ quits, ⌥↩ or ⌥-click force quits, Esc clears the query and then closes. |

Harnesses: `Tests/nc-SystemTools-policy-test.swift` (filtering and sorting, the pam transform, output parsing) and `Tests/nc-SystemTools-module-test.swift` (the switch gating its commands, kill by name, Force Quit asking first, the network test's result, cancel and failure, the Touch ID store on scratch files).
