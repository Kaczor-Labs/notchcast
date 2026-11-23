# Cleaner

The Cleaner model and services cover the current user's app caches. The test harnesses supply their own filesystem and Full Disk Access check.

## Invariants

- A scan offers only direct children of `~/Library/Caches`. The area itself stays in place. Apple and Notchcast caches stay out of the list.
- A complete, readable scan is required for a recommendation. Recent writes, running apps, protected data, unreadable trees and unsafe paths keep rows out of the selection.
- The runner rechecks the parent directories and the selected tree before asking macOS to move it to the Trash. It skips files held open by processes it can inspect. Each selected row gets its own outcome, and one failure leaves the remaining rows eligible.
