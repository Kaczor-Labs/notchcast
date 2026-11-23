# Mac Tweaks

Mac Tweaks has a model for system changes, a journal, and a store with an injected system interface. The store accepts a catalogue when constructed. The app has no registered Mac Tweaks catalogue or settings entry.

## Invariants

- The main app owns one store. The store refuses a second operation while one is running, including while it restarts affected processes. A snapshot does not wait for an operation and reads every target in one pass: each preference domain synchronizes once and `launchctl print-disabled` runs once.
- The live interface writes the current user's any-host preference layer. Managed settings and settings held for this Mac alone block writes. A value from a fallback layer (every app or every account) blocks a tweak only when it already holds the tweak on, as in Peel; otherwise our own layer overrides it.
- The store writes and reads back the journal under the bundle's Application Support directory before changing a setting. A corrupt journal blocks mutations and stays in place.
- Undo restores the exact prior stored value only while the current value matches what Notchcast wrote.
- The store acts only on journal entries whose tweak is in the catalogue and writes that target, with the tweak's own value or a removal. Any other entry stays in the file and is never restored or reported.
- The journal stores each target in one spelling: `.GlobalPreferences` is `NSGlobalDomain`, and `appOnly` is dropped, so one real key has one entry.
- Turning off an active setting with no journal entry removes its preference key and records the prior value for Undo Everything.
- Each affected process restarts once at the end of a batch. A restart whose process is not running counts as done.
- Every child process has a 10 s limit; then it is asked to stop and killed 2 s later, as in Peel.
- The journal and store harnesses use model values, a temporary directory, and a fake system. The store harness compiles the live interface and drives only the fake; it runs real child processes only for the exit-status and time-limit rules.
