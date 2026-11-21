# System page

The SystemMonitor add-on (`Tinycast/Features/Notchcast/SystemMonitor/`, switch `systemPage`, "System in the Island" in Settings › Notchcast › Mac Tweaks, off by default) puts a System page in the open island: CPU, memory, disk and network tiles and the busiest processes, plus a glyph on the closed island while something runs hot. It is an add-on under [addons.md](../addons.md): one folder; the registry is generated from its descriptor's `notchcast-addon-order` comment.

## Invariants

- **No root, no grant.** Every read is a plain syscall an unprivileged process may make: `host_statistics` (CPU), `host_statistics64` and `kern.memorystatus_vm_pressure_level` (memory), the startup volume's resource values (disk), the routing socket's `NET_RT_IFLIST2` 64-bit counters (network) and libproc's `proc_pid_rusage` (processes, read through core `NotchcastProcesses`). A process libproc will not answer for without root (another user's, the kernel's) is left out of the list.
- **Sampling only while it is needed** (decision 946). With the switch on and the island closed, the module reads CPU, memory and disk every 15 s for the hot check and nothing else; it never walks processes or reads network counters, and it posts no page. While Home or the System page shows (`IslandPresenting.watchPages`), it reads everything every 2 s; a read that only set the network and process baseline is followed half a second later, so a short glance shows both. The hidden 15 s wait has a 2 s tolerance so the system can batch the wake-up. Showing the page, hiding it and Command-R each start a fresh loop that reads at once. The switch off stops the loop, removes the page and clears the glyph.
- **Reads leave the main actor.** `MonitorLiveReads.read` is `@concurrent`; one loop, owned by the module, runs at a time and is cancelled by `stop`, and a read that returns after a cancel or switch-off is dropped. The process walk reads every CPU time but names only the five rows it will list, ranked against the previous read's times (`MonitorBoard.ranked`).
- **Thresholds and every word live in `Model/`**, which imports Foundation only and takes each reading, its uptime and the locale as parameters.
- **Hot is never colour alone.** On the page a hot tile's value, bar and note take the warning ink and the note says it in words ("Running hot", "Pressure critical", "Almost full"). On the closed island the glyph is the resource's own symbol with one short word ("Hot", "High", "Full"), and VoiceOver reads every hot resource.

## Hot state

| Resource | Hot when | Cools when |
| --- | --- | --- |
| CPU | at or above 90 % on fresh reads held for 12 s (two hidden reads, or six shown ones) | under 75 %, or a failed read |
| Memory | the kernel reports critical pressure | it no longer does |
| Disk | under 10 % **and** under 20 GB of the startup volume free, on a volume of 10 GB or more | 12 % or more, or 24 GB or more, free |
| Network | never | |

The gap between the marks keeps the glyph from flickering at the limit. Hot resources are named in the order CPU, memory, disk; the closed island shows the first. Its glyph is an `IslandStatus`, so it draws below a level, a notice, the meeting glance and the song (island-shell.md "Presentation API"), as decision 946's priority asks; the Agents page posts nothing to the closed island.

## What it shows

| Where | What |
| --- | --- |
| Page, tiles | A "Resources" row of four cards: CPU load; memory used of total (binary units, as Activity Monitor); disk used of total with the free space under it (decimal units, as Finder); network download over upload per second. A tile with no reading is dimmed with a dash; network says "Measuring…" until it has two reads. |
| Page, processes | "Top processes", then up to five by their share of the whole Mac's CPU between the last two reads, each with its memory footprint; ties by footprint. |
| Home line | The first hot resource ("CPU running hot", its value as detail), else the busier of CPU and memory ("Memory 50%") with the busiest process as detail; the disk appears only while it is hot. |
| Closed island | Nothing, or the hot glyph and word; a click opens the island as every page does. |

Command-R reads at once. There is no launcher command and no settings row.

## Sources of code

Adapted from Vorssaint (GPL-3.0-or-later, `vorssaint/vorssaint-utils@faada18`): the CPU tick delta, the Memory Used formula (app + wired + compressed) and pressure levels, the disk's important-use free space, the interface filter and 64-bit network counters, per-process CPU time over the monitor interval, the 90 % CPU / 10 % disk / critical-pressure limits and the 12 s sustained hold; the 20 GB floor beside the 10 % is ours. Each file keeps Vorssaint's notice and has its lines in `notchcast/licenses/borrowed/SystemMonitor.txt`. Not taken: the menu bar, history graphs, GPU, temperature and fan reads (SMC), per-core bars, grouping helpers under their responsible app (a private libsystem symbol), notifications and their cooldown, and the eject-disk action.

## Proof

- `Tests/nc-SystemMonitor-model-test.swift`: the counters' maths, the CPU hold, its restart on a dip or a failed read and its lower exit mark, memory and disk limits and their order, the disk's percent and byte bounds at both edges, the half-second read after a baseline, rates and their reset on a gap or an interface change, the process ranking and naming, the page, the hot page and the Home line, from injected readings.
- `Tests/nc-SystemMonitor-module-test.swift`: the module as its hook starts it, on a scripted Mac: only plain 15 s reads while hidden, a detail read half a second after the baseline and every 2 s after while shown (on the fake Mac's own clock), the glyph appearing and clearing, its tap, Command-R, nothing read after switch-off, and a read still out when the page hides or the switch goes off (and on again) dropped when it lands.
- `Tests/nc-SystemMonitor-render-test.swift`: PNGs of the page normal, hot and measuring, Home normal and hot, and the closed island's hot glyph, in both forms on Black and Frosted (`977-*`).

## Deviations, numbered for review

1. The closed-island glyph and the Home line draw in the primary ink, not yellow: `IslandStatus` and `IslandPageLine` carry no tone, and `IslandStatusArt` inks every glyph `textPrimary`. Yellow there needs a tone on those values in the island core; the word carries the state meanwhile.
2. The switch sits in Mac Tweaks, as Day's does; a tab for island pages is a core change.
3. Processes are not grouped under their app, so a browser's helpers list one by one.
4. The eject-disk action from #946's inputs is not part of #977; it is #1297.
