# Cleaner

Cleaner scans the current user's app caches, logs, container caches, browser caches and old browser versions, Mail downloads, Homebrew logs, and saved app state. Test harnesses inject a filesystem, a Full Disk Access check and any Trash action.

## Invariants

- A scan offers entries inside known roots. The roots themselves stay in place, and protected data never enters the selection. No-access scans stop before reading the filesystem.
- A complete, readable scan is required for a recommendation. Recent writes, running apps, unreadable trees and unsafe paths keep rows out of the selection. Old browser versions and saved app state start unchecked.
- Review keeps selection separate from the highlighted row and from search. The move confirmation covers the entire selection, including rows outside the current filter.
- The runner rechecks the parent directories and the selected tree before asking macOS to move it to the Trash. It skips files held open by processes it can inspect. Each selected row gets its own outcome, and one failure leaves the remaining rows eligible.
- The Empty Trash offer is a separate question shown only after a move succeeds. Declining it leaves the moved items in the Trash. The reported size describes the items moved.
