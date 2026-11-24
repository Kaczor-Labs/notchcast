# Mac Tweaks

In Settings → Mac Tweaks, turn on System tweaks to see the catalogue. Open Finder to read or change its settings. Undo Everything restores settings recorded in the journal. Turning off System tweaks hides the catalogue and keeps your changes.

## Invariants

- The main app's module owns the store and runs only while System tweaks is on. Every store refuses a second operation while one is running, including while it restarts affected processes and when the module is rebuilt mid-batch.
- The live interface writes the current user's any-host preference layer. Managed settings and settings held in another layer are unavailable for writes.
- The store writes and reads back the journal under the bundle's Application Support directory before changing a setting. A corrupt journal blocks mutations and stays in place.
- Undo restores the exact prior stored value only while the current value matches what Notchcast wrote. It can restore a journal entry even when its tweak is absent from the catalogue.
- Turning off an active preference tweak with no journal entry removes its preference key and records the prior value for Undo Everything. Turning off Show the Library folder in the same situation hides Library and records its prior visibility.
- Each affected process restarts once at the end of a batch.
- A reply without a snapshot (busy, unreadable journal) keeps the last one on screen. A refused or failed request shows a notice with Refresh.
- The journal and store harnesses use model values, a temporary directory, and a fake system. The store harness compiles the live interface and drives only the fake.
