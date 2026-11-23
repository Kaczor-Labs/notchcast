# Cleaner

The Cleaner model and services cover the current user's caches, logs and app leftovers. The test harnesses supply their own filesystem and Full Disk Access check.

## Invariants

- A scan offers only direct children of each area root, never the root itself: `~/Library/Caches`, `~/Library/Logs`, `~/Library/Saved Application State`, both Mail Downloads folders, each app container's `Data/Library/Logs`, `Data/Library/Caches` and `Data/tmp`, each group container's `Library/Caches`, the browser cache folders in `CleanerUserAreas.swift`, and the old framework versions inside Chrome, Edge and Brave. Diagnostic report and Homebrew log areas offer single files at any depth on the root's volume. Apple and Notchcast items stay out of the list.
- Saved app state older than 31 days and browser framework versions older than the one `Current` points to are listed unticked. Mail Downloads rows are always held back. Rows of every other area are pre-ticked when nothing holds them back.
- A complete, readable scan is required for a row to be ticked. Recent writes, running apps (by name, bundle id or maker, such as `Google` for Chrome), a program or script running from inside the row, a repository inside (`.git`, `.hg`, `.svn`, `.jj`, `.pijul`, `_darcs`), protected data, unreadable trees and unsafe paths hold a row back. Outside `~/Library/Caches`, a file held open holds the row back at the scan too.
- The row and every folder above it must be real folders or files. A link or special file inside the row is recorded and not followed, since a move to the Trash never follows it.
- The runner rechecks the parent folders and the whole selected tree before asking macOS to move a row to the Trash, and skips a row a process this account can inspect runs from or holds open. That reading of processes is reused for one second and the walk after it can take two more, so a file opened in those three seconds can still move while open; its process keeps writing to it in the Trash.
- After the move, the runner compares the item macOS reports in the Trash with the scanned identity; a mismatch is reported as unverified, not as trashed. A failed move keeps its `CocoaError` code. Each selected row gets its own outcome, and one failure leaves the remaining rows eligible.
