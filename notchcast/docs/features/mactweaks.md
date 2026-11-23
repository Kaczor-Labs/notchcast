# Mac Tweaks

Mac Tweaks has a model for system changes, a journal, and a store with an injected system interface. The store accepts a catalogue when constructed. The app has no registered Mac Tweaks catalogue or settings entry.

## Invariants

- The main app owns one store. The store refuses a second operation while one is running, including while it restarts affected processes.
- The live interface writes the current user's any-host preference layer. Managed settings and settings held in another layer are unavailable for writes.
- The store writes and reads back the journal under the bundle's Application Support directory before changing a setting. A corrupt journal blocks mutations and stays in place.
- Undo restores the exact prior stored value only while the current value matches what Notchcast wrote. It can restore a journal entry even when its tweak is absent from the catalogue.
- Turning off an active setting with no journal entry removes its preference key and records the prior value for Undo Everything.
- Each affected process restarts once at the end of a batch.
- The journal and store harnesses use model values, a temporary directory, and a fake system. The store harness compiles the live interface and drives only the fake.
