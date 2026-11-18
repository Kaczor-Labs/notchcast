# System page

The System add-on (`Tinycast/Features/Notchcast/System/`, switch `systemPage`, "System in the Island" in Settings › Notchcast › Mac Tweaks, off by default) puts a System page in the open island and a warning in the closed one when the Mac runs hot (#977, decision 946-3). It is an add-on under [addons.md](addons.md): one folder, one registry line, no upstream or core file.

## Invariants

- **No privileges.** Every read is one an ordinary user process may make; a process the user may not read is left out of the list, never asked for with root or a helper.
- **Nothing runs while the switch is off.** `SystemModule.start` owns the one sampling task and `stop` cancels it, removes the page and clears the status.
- **Thresholds, the hot state and every word on the page live in `Model/`**, which imports Foundation only and takes samples, times and the locale as parameters. Nothing there reads a clock or the Mac.
- **A warning is a glyph and words, never colour alone**: `exclamationmark.triangle.fill` with its title on the page and on Home, and with a word of at most four characters in the closed island.
- **The add-on draws nothing.** It posts an `IslandPage` and an `IslandStatus`; the island draws both (design-system.md §12, §17).

## What it shows

| Where | What |
| --- | --- |
| Page, top | One row per warning that holds: glyph, title, one sentence. |
| Page, tiles | CPU, Memory and Disk as meters (share used; "9 GB of 16 GB", "212 GB free"), Network as a row with down and up in bytes a second, a dash while there is no rate. |
| Page, list | "Top Processes": up to five process names by share of the whole Mac's CPU, helpers summed under their shared name, none under half a percent. |
| Home line | The busier of CPU and memory with the other as its detail; while a warning holds, the most urgent warning with the busier resource as its detail. |
| Closed island | While a warning holds, the glyph and a short word (`Hot`, `RAM`, `CPU`, `Disk`) as the status `system.hot`; VoiceOver reads the warning's title. Nothing otherwise. |

Command-R on the page reads at once. The page has no buttons and no badge: nothing on it waits for the user.

## Hot state

`SystemHotState` (`Model/SystemHotState.swift`) decides after each reading which warnings hold, most urgent first; the closed island and Home show the first.

| Warning | Holds while | Constant |
| --- | --- | --- |
| Running Hot | the system's thermal state is serious or critical | `SystemThermal.serious` |
| Memory Pressure | the kernel's memory pressure level is critical | `SystemMemoryPressure.critical` |
| CPU High | CPU load has been at or above 90% across separate reads for 12 s | `cpuLimit`, `cpuSustainedSeconds` |
| Disk Almost Full | under 10% of a volume of 10 GB or more is free | `diskFreeLimit`, `diskMinimumBytes` |

A warning ends with the first reading under its limit. A pause in sampling ends a CPU stretch, so load before the pause never counts toward the 12 s.

In the closed island the status sits in the island's status layer, under a level, a notice and the meeting glance (island-shell.md "Presentation API"). It is sent only when it changes, because setting a status makes it the island's newest.

## Sampling

`SystemModule` (`Service/`) reads once when the switch goes on, again after 1 s so the first rate exists, then every 15 s (`interval`, decision 946's background cadence). One read (`SystemProbe.sample`, off the main actor) serves the page and the hot check. A rate is the difference between two reads (`SystemReading`): reads closer than 0.5 s make none and keep the older baseline, a gap over 60 s only starts a new baseline. A read that returns after `stop` is dropped.

`SystemProbe` reads the CPU ticks (`host_statistics`), memory as Activity Monitor counts Memory Used (`host_statistics64`: app memory less purgeable, wired, compressed), the kernel's pressure level, the free and total space of the volume holding the home folder (important-use capacity, as Finder counts free space), 64-bit byte counters of the physical network interfaces (`NET_RT_IFLIST2`), each readable process's CPU time (`proc_pid_rusage`) and `ProcessInfo.thermalState`.

## Sources

Adapted from Vorssaint (GPL-3.0-or-later, `vorssaint/vorssaint-utils@89d2626`): the counter-delta rates and gap guards, the memory formula, the counted-interface rule, the per-process CPU share and the sustained alert gate. Each derived file keeps Vorssaint's notice and has a line in `notchcast/licenses/borrowed.md`. Not taken: SMC sensors, fan and GPU readings, per-process network and energy, history graphs, notifications.

## Proof

- `Tests/nc-System-model-test.swift`: rates, gap guards, process ranking, the memory formula, every threshold and the page, Home line and status, from injected samples.
- `Tests/nc-System-module-test.swift`: the module as its hook starts it on a scripted Mac with a sleep that takes no time: cadence, the page appearing with the first rate, the status set once and cleared, Command-R, switch off and on, and a read that returns after switch-off.
- `Tests/nc-System-render-test.swift` and `Tests/nc-System-status-render-test.swift`: PNGs of the page and Home, normal and hot, and of the hot closed island, in both forms on Black and Frosted (`977-*`, uploaded by CI as `island-renders-<shard>`).

## Deviations, numbered for review

1. The four tiles are three meters and a row, the blocks #975 ships; a tile grid would be a new block in the pages core.
2. The warning glyph is not yellow: `IslandPageRow`, `IslandPageLine` and `IslandStatus` carry no tone, so it draws in the text ink. Yellow needs a tone on those values in the island core.
3. The page reads every 15 s whether it is open or not: `setPage` gives an owner no signal that its page is showing, so decision 946's 2 s cadence while open is not built. Command-R reads at once.
4. The status takes the island's status order (the newest shows first), so "below agent, meeting, music" holds for the meeting glance only; ranking it against an agent or player status needs a rank in the island core once those exist.
5. The switch sits in Mac Tweaks, the one shown tab that fits; a tab of its own for island pages is a core change.

Not verified: any of it live (the probe against a real Mac, the page and status in the running island, VoiceOver); only CI compiles and renders it.
