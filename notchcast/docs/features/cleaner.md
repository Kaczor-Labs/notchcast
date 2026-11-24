# Cleaner

Cleaner scans the current user's app caches, logs, container caches, browser caches and old browser versions, Mail downloads, Homebrew logs, and saved app state. The Cleaner switch sits in Mac Tweaks. Its Clean Up Mac command opens the review in the palette and starts a scan; closing the screen cancels the scan, and Command-R scans again. The same command is Low Disk's Clean Up offer while space is low. Test harnesses inject a filesystem, a Full Disk Access check and any Trash action.

## Invariants

- A scan offers entries inside known roots. The roots themselves stay in place, and protected data never enters the selection. No-access scans stop before reading the filesystem.
- A complete, readable scan is required for a recommendation. Recent writes, running apps, unreadable trees and unsafe paths keep rows out of the selection. Old browser versions and saved app state start unchecked.
- Review keeps selection separate from the highlighted row and from search. The footer counts all selected items and how many the filter hides. When selected items are hidden, Show Selected Items clears the filter and preserves the checks so all selected rows can be reviewed before Move to Trash.
- The runner rechecks the parent directories and the selected tree before asking macOS to move it to the Trash. It skips files held open by processes it can inspect. Each selected row gets its own outcome, and one failure leaves the remaining rows eligible.
- The Empty Trash offer is a separate destructive question, answered Empty Trash or Not Now, shown only after a move succeeds and while its setting is on. A held Return or Enter cannot answer it. Confirming runs the stock Empty Trash action. Not Now leaves the moved items in the Trash. The result keeps missing, skipped and failed items distinct and shows the move result alongside any Trash result from Finder. The reported size describes the items moved.
