# Borrowed add-on sources

Each add-on file derived from another project keeps that project's notice in its own header and is listed, one line per file, in its add-on's own list `notchcast/licenses/borrowed/<add-on folder>.txt`. An add-on branch writes only its own list, so two add-on PRs never edit one file; `notchcast/check-addons.py` fails an entry written here. Upstream's `NOTICE.md` ships in the app bundle and points here.

Format of each line: `<add-on folder>: <our file> ← <source repo>/<source file> (<licence>)`, with our file relative to `Tinycast/Features/Notchcast/<add-on folder>/`.
