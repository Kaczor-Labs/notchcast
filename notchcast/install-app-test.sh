#!/bin/bash
# install-app.sh against synthetic bundles; fake open/osascript/launchctl on PATH, so no real app or agent is touched.
set -euo pipefail
WORK="$(mktemp -d)"
export WORK HOME="$WORK/home" PATH="$WORK/bin:$PATH"
export NOTCHCAST_APP="$WORK/Installed.app" NOTCHCAST_WATCH_SECONDS=3 NOTCHCAST_TRASH="$WORK/Trash"
cleanup() { pkill -f "^$WORK/" 2>/dev/null || true; rm -rf "$WORK"; }
trap cleanup EXIT
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$HOME" "$WORK/bin"
cp "$HERE/install-app.sh" "$HERE/config.env" "$WORK/"
cat > "$WORK/bin/launchctl" <<'FAKE'
#!/bin/bash
echo "$*" >> "$WORK/launchctl.log"
FAKE
# Launches the bundle as LaunchServices would: argv[0] is the executable's full path.
cat > "$WORK/bin/open" <<'FAKE'
#!/bin/bash
echo "$*" >> "$WORK/open.log"
[ "$1" = -g ] && [ "$#" = 2 ] && [[ "$2" = "$WORK"/* ]] || exit 1
nohup "$2/Contents/MacOS/test-app" "$(cat "$2/Contents/Resources/lifetime")" </dev/null >/dev/null 2>&1 &
FAKE
cat > "$WORK/bin/osascript" <<'FAKE'
#!/bin/bash
echo "$*" >> "$WORK/osascript.log"
if [ -e "$WORK/hang-quit" ]; then exec -a "$WORK/hung-osascript" /bin/sleep 300; fi
pkill -TERM -f "^$WORK/" || true
FAKE
chmod +x "$WORK/bin/"*
bundle() { # name version seconds-alive
    local path="$WORK/$1.app"
    mkdir -p "$path/Contents/MacOS" "$path/Contents/Resources"
    printf '%s\n' '<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>test-app</string><key>CFBundleShortVersionString</key>' "<string>$2</string></dict></plist>" > "$path/Contents/Info.plist"
    cat > "$path/Contents/MacOS/test-app" <<'APP'
#!/bin/bash
exec -a "$0" /bin/sleep "$1"
APP
    chmod +x "$path/Contents/MacOS/test-app"
    echo "$3" > "$path/Contents/Resources/lifetime"
}
pids() { pgrep -f "^$NOTCHCAST_APP/Contents/MacOS/" || true; }
installed() { /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$NOTCHCAST_APP/Contents/Info.plist"; }
fail() { echo "FAIL: $*"; cat "$WORK/log" 2>/dev/null; exit 1; }
bundle Old 1.0.0 600
bundle New 2.0.0 600
bundle Crashing 3.0.0 1
bundle Newer 4.0.0 600

ditto "$WORK/Old.app" "$NOTCHCAST_APP"
open -g "$NOTCHCAST_APP"
for _ in $(seq 1 20); do [ -z "$(pids)" ] || break; sleep 0.25; done
OLD_PID="$(pids)"
[ -n "$OLD_PID" ] || fail 'old app did not start'
rm "$WORK/open.log"
"$WORK/install-app.sh" "$WORK/New.app" > "$WORK/log" 2>&1 || fail 'running install exited non-zero'
grep -qx 'left running: 2.0.0 (new)' "$WORK/log" || fail 'new app not left running'
grep -qxF 'tell application id "app.notchcast" to quit' <(sed 's/^-e //' "$WORK/osascript.log") || fail 'no quit by bundle id'
grep -qxF -- "-g $NOTCHCAST_APP" "$WORK/open.log" || fail 'new app not opened in the background'
NEW_PID="$(pids)"
if [ -z "$NEW_PID" ] || [ "$NEW_PID" = "$OLD_PID" ] || kill -0 "$OLD_PID" 2>/dev/null; then fail 'old app not replaced'; fi
[ "$(installed)" = 2.0.0 ] || fail 'wrong version installed'
echo 'PASS: running app quit, new bundle opened and watched'

STATUS=0
"$WORK/install-app.sh" "$WORK/Crashing.app" > "$WORK/log" 2>&1 || STATUS=$?
[ "$STATUS" = 1 ] || fail "crashing install exited $STATUS"
grep -qx 'left running: 2.0.0 (previous)' "$WORK/log" || fail 'previous app not restored and running'
[ "$(installed)" = 2.0.0 ] && [ -n "$(pids)" ] || fail 'previous app not back in place'
compgen -G "$NOTCHCAST_TRASH/Notchcast failed 3.0.0 *.app" > /dev/null || fail 'crashing bundle not in the Trash'
echo 'PASS: crashing bundle rolled back to the previous one, which runs'

pkill -f "^$WORK/"
for _ in $(seq 1 20); do [ -n "$(pids)" ] || break; sleep 0.25; done
rm -f "$WORK/open.log" "$WORK/osascript.log"
"$WORK/install-app.sh" "$WORK/Newer.app" > "$WORK/log" 2>&1 || fail 'idle install exited non-zero'
grep -qx 'left running: nothing (app was not running; launch skipped; installed 4.0.0)' "$WORK/log" || fail 'idle install log'
[ "$(installed)" = 4.0.0 ] || fail 'idle install did not install'
sleep 1
[ -z "$(pids)" ] && [ ! -e "$WORK/open.log" ] && [ ! -e "$WORK/osascript.log" ] || fail 'idle install launched or quit the app'
echo 'PASS: app not running: installed, not launched'

open -g "$NOTCHCAST_APP"
for _ in $(seq 1 20); do [ -z "$(pids)" ] || break; sleep 0.25; done
[ -n "$(pids)" ] || fail 'app did not start before the hung quit'
rm -f "$WORK/osascript.log"; touch "$WORK/hang-quit"
HUNG_PID="$(pids)"
NOTCHCAST_QUIT_SECONDS=2 "$WORK/install-app.sh" "$WORK/New.app" > "$WORK/log" 2>&1 &
INSTALL=$!
for _ in $(seq 1 60); do kill -0 "$INSTALL" 2>/dev/null || break; sleep 0.25; done
if kill -0 "$INSTALL" 2>/dev/null; then kill "$INSTALL"; fail 'hung quit install still running after 15 seconds'; fi
STATUS=0
wait "$INSTALL" || STATUS=$?
[ "$STATUS" = 1 ] || fail "hung quit install exited $STATUS"
grep -qx 'the running app did not quit within 2 seconds' "$WORK/log" || fail 'no quit deadline log'
grep -qx 'left running: 4.0.0 (previous, never quit, not restarted)' "$WORK/log" || fail 'wrong final after the hung quit'
[ "$(pids)" = "$HUNG_PID" ] || fail 'the app that never quit is not the one left running'
[ "$(grep -c . "$WORK/osascript.log")" = 1 ] || fail 'rollback asked the hung app to quit again'
pgrep -f "^$WORK/hung-osascript" >/dev/null && fail 'hung osascript left alive'
[ "$(installed)" = 4.0.0 ] || fail 'previous bundle not restored after the hung quit'
echo 'PASS: a Quit that never answers hits the deadline and rolls back'

[ ! -e "$WORK/launchctl.log" ] || fail "install-app.sh ran launchctl: $(cat "$WORK/launchctl.log")"
echo 'PASS: no launchctl'
