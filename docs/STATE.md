# Notchcast state

The one state file of the fork: Damian's decisions first, then Current, Next, Log. How the fork works is in [notchcast/README.md](../notchcast/README.md); our docs live in [notchcast/docs/](../notchcast/docs/).

## Damian's decisions (binding, check before asking him)

- Everything lives in the black island: every stock Tinycast feature, questions, reports, menus and every HUD.
- Screens without a notch get a pill; his notchless ultrawide is the primary case.
- Settings, Notes and the window-layout editor stay real windows.
- Black only: no light theme and no custom themes, ever (a Liquid Glass variant may come later).
- English only; new strings need no translations.
- Raycast Extensions and Support are hidden.
- Unused upstream features are hidden, never cut: off and gone from every surface, code kept; the list is only [notchcast/docs/hidden.md](../notchcast/docs/hidden.md).
- Add-ons are plug-and-play: one folder and one registry line to add or remove.
- Upstream sync stays trivial: touch as few upstream files and lines as possible, so our commits replay onto every upstream commit.
- Upstream's root `AGENTS.md` and `docs/` stay as upstream ships them, apart from this file; our rules go in `notchcast/`.
- The name changes only where it shows, at build time; `LICENSE`, `NOTICE.md` and the `.tinycast` backup type stay.
- Built is not accepted: a feature counts as accepted only once Damian has tried it in use.
- Cutover 2026-11-15: `main` is v2; v1 is kept as branch `v1/final` and tag `v1-final`.

## Current

- `main` is v2; units land one at a time through `notchcast/land.sh` after the commander's accept.

## Next

- Kept in the maintainers' tracker, not here.

## Log

- Landings are the squash commits on `main` (`git log --first-parent main`); nothing is copied here.
