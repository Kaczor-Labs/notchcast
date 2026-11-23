# Threads

The Threads add-on (`Tinycast/Features/Notchcast/Threads/`, switch `threads`, Settings › Notchcast › Agents) shows the agent threads that wait on the user. It reads t3chad's `waits` document (v1), which t3chad rewrites about once a minute, posts an island notice when a thread starts waiting, keeps a count on the resting island and lists every wait on a Threads page. A click on a notice, a row or a thread's launcher command opens that thread in T3.

## Invariants

- **The file path is local.** Settings › Notchcast › Agents › Waits file stores it in the `.notchcast` suite (`threads.waitsFile`) and starts empty, so the repo names no path; with no path the add-on shows nothing at all.
- **Read on change, never on a timer.** One read when the module starts, then one per file event on the file or its folder (`ThreadsWatcher`; a writer's rename shows on the folder). The one timer is a one-shot expiry at a fresh document's 5-minute deadline: it only redraws the list as silent and never reads. A folder that is missing is armed again when the page comes on show, on Command-R or when Settings picks a file.
- **A wait is announced once, ever.** Announced ids are kept in the suite (`threads.shownWaits`; an id is dropped only once its wait leaves the file), so a restart or a reread announces nothing again. A wait without an `id` (a t3chad older than the field) and a door ask marked `later` are listed but never announced. A document older than 5 minutes announces nothing.
- **Silence is shown, never read as "nothing waits".** A document older than 5 minutes, or a failed latest read (a vanished or broken file), puts "t3chad is not reporting" at the top at once and keeps the last good list under it; a machine whose own reading is older than 5 minutes gets its own line. Nothing errors on the island; the cause of a failed read goes to the unified log, category `Threads`.
- **Several new waits are one notice; a failed run is always its own** (failure tone). The count turns red while a failed run waits.
- **Only T3's link opens.** A row, notice or command opens `t3code://threads/<environment>/<thread>`, built only from ids of letters, digits, `-`, `_`, `.` and `:` (a `prefix:` id goes out as one segment, the colon as `%3A`); anything else leaves the row unclickable, and nothing but that scheme reaches `NSWorkspace`.
- **One launcher command per waiting thread**, published at run time with a slug from the wait's id, plus the declared Open Threads. Asks that share a thread share one command, and a changed target republishes it.

`Tests/nc-Threads-module-test.swift` starts the module as its hook does on a scratch suite and file: decoding, every page state, notices, links, announce-once across a restart and past 500 newer waits, old, missing and broken files, the silent expiry, opening, commands that follow their thread and one real file event. `Tests/nc-Threads-page-render-test.swift` and `Tests/nc-Threads-notice-render-test.swift` (hosted-only) render every page state, notice and count from made-up documents in both forms, Black and Frosted.

## Hand test

Set the waits file in Settings, let a thread ask something in T3 (or let a run fail): within a few minutes the island announces it once; click the notice and T3 opens on that thread. Quit and reopen Notchcast: no notice repeats.

Known gap: threads stopped on a plan limit are not listed under "Not waiting on you", since the waits document does not carry them.
