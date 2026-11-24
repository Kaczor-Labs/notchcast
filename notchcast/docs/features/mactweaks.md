# Mac Tweaks

In Settings → Mac Tweaks, turn on System tweaks to see the catalogue. Open Finder to read or change its settings. Undo Everything restores settings recorded in the journal. Turning off System tweaks hides the catalogue and keeps your changes.

## Invariants

- The main app owns one store. The store refuses a second operation while one is running, including while it restarts affected processes. A snapshot does not wait for an operation and reads every target in one pass: each preference domain, and the global domain behind it, synchronizes once, a failed sync fails every key of that domain, and `launchctl print-disabled` runs once. A snapshot reads the journal before and after the system read and retries until both match, so no value comes without its undo data. `isCurrent` rejects a snapshot once a newer one was asked for or an operation ran since it began.
- The live interface writes the current user's any-host preference layer. Managed settings and settings held for this Mac alone block writes. A value from a fallback layer (every app or every account) blocks a tweak only when it already holds the tweak on, as in Peel; otherwise our own layer overrides it.
- The store writes and reads back the journal under the bundle's Application Support directory before changing a setting. A corrupt journal blocks mutations and stays in place.
- Undo restores the exact prior stored value only while the current value matches what Notchcast wrote.
- The store acts only on journal entries whose tweak is in the catalogue and writes that target, with the tweak's own value, a removal, or the hidden Library that turning off Show the Library folder writes. Any other entry stays in the file, is never restored, and Undo Everything reports it as skipped. A release that drops a tweak keeps it in the catalogue as retired: unsupported, still restored by Undo Everything.
- A write to a target whose journal entry only a retired or unknown tweak explains is refused and reported, so that entry keeps its prior value for Undo Everything.
- The journal stores each target in one spelling: `.GlobalPreferences` is `NSGlobalDomain`, and `appOnly` is dropped, so one real key has one entry.
- Turning off an active preference tweak with no journal entry removes its preference key and records the prior value for Undo Everything. Turning off Show the Library folder in the same situation hides Library and records its prior visibility.
- Each affected process restarts once at the end of a batch. A restart counts as done when `killall` reports no matching process; any other failure, including a refused signal, is reported.
- Every child process has a 10 s limit, as in Peel: then it is asked to stop, killed 2 s later, and given up on 2 s after that. A child that was asked to stop counts as stopped even if it then exits zero. Output is read for at most 0.5 s after the child exits, so a descendant holding the pipe cannot hold the result. One thread signals and reaps the child, so a signal never reaches a reused process ID.
- The RemoveMacAI MIT notice ships in the app bundle as `RemoveMacAI-MIT.txt`, and `notchcast/licenses/borrowed/MacTweaks.txt` pins its source files so the borrowed-code watch sees it.
- The journal and store harnesses use model values, a temporary directory, and a fake system. The store harness compiles the live interface and drives only the fake; it runs real child processes only for the exit-status, time-limit and pipe rules.
