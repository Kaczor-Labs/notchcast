#!/bin/bash
# Hosted tester scenario: launch the Debug app, type, click an unselected row, press Return. PNGs + logs in $OUT.
set -uo pipefail
OUT=${OUT:?}
APP=${APP:?}
[ "${RUNNER_ENVIRONMENT:-}" = github-hosted ] || { echo "launcher.sh drives the screen: GitHub-hosted runner only" >&2; exit 2; }
mkdir -p "$OUT"
fail=0
log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$OUT/scenario.log"; }
shot() { screencapture -x "$OUT/$1.png" && log "shot $1" || { log "shot $1 FAILED"; fail=1; }; }
check() { if [ "$2" = 0 ]; then log "PASS $1"; else log "FAIL $1"; fail=1; fi; }
# Polls a command until it succeeds, at most $1 seconds: the app under test sends no event to wait on.
until_ok() { local cap=$1; shift; for ((i = 0; i < cap * 4; i++)); do "$@" >/dev/null 2>&1 && return 0; sleep 0.25; done; return 1; }
running() { pgrep -xq "$1"; }
se() { osascript -e "tell application \"System Events\" to $1"; }
palette_up() { [ -n "$(se 'tell process "Notchcast Dev" to get name of every window' 2>/dev/null)" ]; }
# Every static text in the app's windows as "value<TAB>centre x<TAB>centre y".
rows() {
  osascript -l JavaScript -e '
    const p = Application("System Events").processes.byName("Notchcast Dev"); const out = [];
    for (const w of p.windows()) for (const e of w.entireContents()) {
      try { if (e.role() !== "AXStaticText") continue; const v = e.value() || e.name(); if (!v) continue;
        const [x, y] = e.position(), [wd, h] = e.size(); out.push(`${v}\t${x + Math.round(wd / 2)}\t${y + Math.round(h / 2)}`) } catch (_) {}
    }
    out.join("\n")' 2>>"$OUT/scenario.log"
}
# A real HID mouse move, down and up: System Events' "click at" presses the AX element and skips the row's tap.
click() {
  osascript -l JavaScript -e 'function run([x, y]) { ObjC.import("CoreGraphics"); const p = $.CGPointMake(+x, +y);
    for (const type of [$.kCGEventMouseMoved, $.kCGEventLeftMouseDown, $.kCGEventLeftMouseUp]) {
      $.CGEventPost($.kCGHIDEventTap, $.CGEventCreateMouseEvent(null, type, p, $.kCGMouseButtonLeft)); delay(0.1) } }' "$1" "$2"
}
has_row() { rows | cut -f1 | grep -qx "$1"; }
app_exists() { [ -d "/System/Applications/$1.app" ] || [ -d "/System/Applications/Utilities/$1.app" ] || [ -d "/Applications/$1.app" ]; }
reopen() { open "$APP"; until_ok 10 palette_up; }

log "runner: $(uname -m), macOS $(sw_vers -productVersion), $(system_profiler SPDisplaysDataType 2>/dev/null | grep -i resolution | xargs)"
mkdir -p "$HOME/Library/Application Support/app.notchcast.dev"
touch "$HOME/Library/Application Support/app.notchcast.dev/onboarded"
open --stdout "$OUT/app.stdout.log" --stderr "$OUT/app.stderr.log" "$APP"
until_ok 30 running "Notchcast Dev"; check "app launched" $?
shot 01-launched
# A second open is a reopen, which shows the launcher.
reopen; check "palette opened" $?
shot 02-palette

query=Cal
se "keystroke \"$query\""
target=
for ((t = 0; t < 40 && ${#target} == 0; t++)); do
  sleep 0.25
  rows > "$OUT/rows.tsv"
  # The first app row is the selected one; the next app row is the click target.
  target=$(cut -f1 "$OUT/rows.tsv" | while read -r name; do app_exists "$name" && echo "$name"; done | awk '!seen[$0]++' | sed -n 2p)
done
shot 03-typed
if [ -n "$target" ] && ! running "$target"; then
  IFS=$'\t' read -r _ cx cy < <(awk -F'\t' -v n="$target" '$1 == n {print; exit}' "$OUT/rows.tsv")
  log "click unselected row '$target' at $cx,$cy"
  click "$cx" "$cy" >>"$OUT/scenario.log" 2>&1
  until_ok 20 running "$target"; check "click on unselected row opened $target" $?
  sleep 2
  shot 04-after-click
else
  log "rows for '$query': $(cut -f1 "$OUT/rows.tsv" | paste -sd '|' -)"
  check "click target: a second app row, not running" 1
fi

running "Activity Monitor"; check "Activity Monitor not running before Return" $((!$?))
reopen; check "palette reopened" $?
se 'keystroke "Activity Monitor"'
until_ok 10 has_row 'Activity Monitor'
shot 05-typed-activity
se 'key code 36'
until_ok 20 running "Activity Monitor"; check "Return opened Activity Monitor" $?
sleep 2
shot 06-after-return

command log show --style compact --last 10m --predicate 'process == "Notchcast Dev"' > "$OUT/app.unified.log" 2>&1
log "result: $([ $fail = 0 ] && echo PASS || echo FAIL)"
exit $fail
