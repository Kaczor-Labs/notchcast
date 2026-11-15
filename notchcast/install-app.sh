#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/config.env"
APP="${NOTCHCAST_APP:-/Applications/$APP_NAME.app}"
WATCH="${NOTCHCAST_WATCH_SECONDS:-60}"
QUIT="${NOTCHCAST_QUIT_SECONDS:-20}"
TRASH="${NOTCHCAST_TRASH:-$HOME/.Trash}"
PREVIOUS="$HOME/Library/Application Support/notchcast/previous/$APP_NAME.app"
if [ -n "${NOTCHCAST_APP:-}" ]; then PREVIOUS="$(dirname "$APP")/previous/$APP_NAME.app"; fi
version() { /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$1/Contents/Info.plist" 2>/dev/null || echo unknown; }
log() { printf '%s\n' "$*"; }
FINAL='nothing (installation interrupted)'
trap 'log "left running: $FINAL"' EXIT
[[ "$WATCH" =~ ^[0-9]+$ ]] || { FINAL='nothing (invalid watch seconds)'; exit 2; }
[[ "$QUIT" =~ ^[1-9][0-9]*$ ]] || { FINAL='nothing (invalid quit seconds)'; exit 2; }
# One install at a time: a second one exits 75 and touches nothing.
if [ -z "${NOTCHCAST_INSTALL_LOCKED:-}" ] && [ -d "${1:-}/Contents" ]; then
    mkdir -p "$(dirname "$PREVIOUS")"
    trap - EXIT
    NOTCHCAST_INSTALL_LOCKED=1 exec lockf -k -t 0 "$(dirname "$PREVIOUS")/install.lock" "$0" "$@"
fi
[ "$#" = 1 ] && [ -d "$1/Contents" ] || { FINAL='nothing (usage: install-app.sh <new.app>)'; exit 2; }
NEW_VERSION="$(version "$1")"
trash() {
    local target
    target="$TRASH/$APP_NAME $2 $(date +%Y%m%d-%H%M%S)-$$.app"
    mkdir -p "$TRASH"
    mv "$1" "$target"
}
app_pids() { pgrep -f "^$APP/Contents/MacOS/" || true; }
# The same pid must stay up for WATCH seconds; a crash or a self-relaunch both fail it.
watch_app() {
    local pid='' start=$SECONDS
    while [ -z "$pid" ]; do
        if (( SECONDS - start >= 15 )); then return 1; fi
        sleep 0.5
        pid="$(app_pids | head -1)"
    done
    start=$SECONDS
    while (( SECONDS - start < WATCH )); do
        app_pids | grep -qx "$pid" || return 1
        sleep 1
    done
    app_pids | grep -qx "$pid"
}
# Quit by bundle id, as the user would, then open in the background so focus stays put.
restart_app() {
    if [ -n "$(app_pids)" ]; then
        # In the background, so a Quit that never answers still hits the deadline.
        osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 &
        local quit=$! start=$SECONDS
        while [ -n "$(app_pids)" ] && (( SECONDS - start < QUIT )); do sleep 0.5; done
        kill "$quit" 2>/dev/null || true
        if [ -n "$(app_pids)" ]; then log "the running app did not quit within $QUIT seconds"; return 1; fi
    fi
    open -g "$APP"
}
RUNNING=0
if [ -n "$(app_pids)" ]; then RUNNING=1; fi
mkdir -p "$(dirname "$PREVIOUS")" "$(dirname "$APP")"
HAD_PREVIOUS=0
if [ -e "$APP" ]; then
    if [ -e "$PREVIOUS" ]; then trash "$PREVIOUS" "previous $(version "$PREVIOUS")"; fi
    mv "$APP" "$PREVIOUS"
    HAD_PREVIOUS=1
elif [ -e "$PREVIOUS" ]; then
    HAD_PREVIOUS=1
fi
if ditto "$1" "$APP"; then
    if [ "$RUNNING" = 0 ]; then
        FINAL="nothing (app was not running; launch skipped; installed $NEW_VERSION)"
        exit 0
    fi
    if restart_app && watch_app; then
        FINAL="$NEW_VERSION (new)"
        exit 0
    fi
fi
log "installation did not stay alive; restoring previous app"
if [ -e "$APP" ]; then trash "$APP" "failed $NEW_VERSION"; fi
if [ "$HAD_PREVIOUS" = 1 ]; then
    mv "$PREVIOUS" "$APP"
    if [ "$RUNNING" = 0 ]; then
        FINAL="nothing (app was not running; restored $(version "$APP"))"
    elif restart_app && watch_app; then
        FINAL="$(version "$APP") (previous)"
    else
        FINAL="nothing (restored $(version "$APP") did not stay alive)"
    fi
else
    FINAL='nothing (no previous app to restore)'
fi
exit 1
