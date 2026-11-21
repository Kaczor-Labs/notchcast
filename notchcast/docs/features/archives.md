# Archives

The Archives add-on (`Tinycast/Features/Notchcast/Archives/`), under the **Archives** switch in Settings › Notchcast › Downloads, extracts archives in place of Archive Utility and compresses a Finder selection. Progress, results and failures are island notices; a question goes through the core's `confirm` dialog.

## Invariants

- **Nothing is bundled.** Every tool is the user's own install, found with `ExecutableLocator.locate`; a missing one is a failure notice naming it and its install line.
- **Never over an existing file.** Output takes the first free name (`ArchivePlacement.freeName`: `Trip`, `Trip 2`, `Trip 3`…). Extraction moves staged items into place by rename; compression publishes with `renamex_np(RENAME_EXCL)` and moves on to the next number if a name was taken meanwhile; where the disk lacks it (exFAT, SMB: `ENOTSUP`), with `FileManager.moveItem`, which also refuses a taken name but not atomically.
- **Output lands beside the input**: extracted items beside the archive, an archive beside the selection.
- **A stop or failure leaves nothing half-done.** Extraction keeps only what HatchZip already moved out in place; compression writes in a private folder on the output's volume (`.itemReplacementDirectory`), removed on every exit, and publishes on the main actor after checking for a stop.
- **One extraction and one compression at a time.** Extraction is a queue journalled to `archives.json`, so a relaunch resumes it; compression is in memory only, and a second request while one runs is refused with a notice. The two run side by side.

## Extract

Opening an archive with Notchcast (or "Extract Archive…") queues it. `ArchiveRoute` picks the engine from the name: HatchZip for most formats, bsdtar, unar, or a single-stream decompressor under a size cap. A listing is checked by `ArchiveSafety` before anything is written. One top-level item lands beside the archive under its own name; several land in a folder named after the archive. "Extract in place" removes the archive as its files come out, for when keeping it does not fit; HatchZip asks for that itself when space runs out. "Make Notchcast the default app for archives" claims the archive types once, and switching the add-on off hands them back.

## Compress

"Compress to ZIP", "Compress to 7z" and "Compress to .tar.zst" read Finder's selection through the core's `NotchcastAppleEvents.finderSelection` (Automation refused becomes our own notice) and make one archive:

- one item is named after itself with its whole name (`notes.txt.zip`, `Photos.7z`); several are named after their folder (`Trip.tar.zst`), the number going before the whole extension (`Trip 2.tar.zst`); a long name is cut to fit 255 bytes, its extension and a number, never through a character;
- refused before any tool runs: nothing selected, items from more than one folder, `/`, anything that is not a file, folder or symbolic link, a folder Notchcast cannot write to;
- the island shows a progress notice while it runs; a tap on it asks before stopping; a tap on the result reveals it in Finder.

| Format | Tool | Install | Command line |
| --- | --- | --- | --- |
| ZIP | `ditto` | ships with macOS | `ditto -c -k --sequesterRsrc [--keepParent] <item> <out>`; several items, or a lone link, are cloned into a private folder and zipped from there, so they sit at the top level and links stay links |
| 7z | `7zz`, else `7z` | `brew install sevenzip` | `7zz a -t7z -mx=9 -snl -spd -bd -y -- <out> <absolute paths>` |
| .tar.zst | `bsdtar` and `zstd` | `brew install zstd` | `bsdtar --use-compress-program "<zstd>" -cf <out> -C <folder> ./<name>…`; stock bsdtar cannot write zstd itself, so the located `zstd` is passed, quoted, with `\` and `"` escaped |

`Tests/nc-Archives-model-test.swift` covers routing, naming, refusals and every argument list; `nc-Archives-module-test.swift` drives extraction with fake tools; `nc-Archives-compress-test.swift` drives compression with fake tools. Not verified by a harness: the real tools, which only a hand run exercises.
