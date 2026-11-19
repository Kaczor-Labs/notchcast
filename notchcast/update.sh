#!/bin/bash
# Notchcast updater: install the newest snapshot at /Applications/Notchcast.app; install-app.sh restarts the app
# only if it was running. Runs from launchd (notchcast.update) and from install-launchd.sh (first install).
# It installs only a build with our bundle id (BUNDLE_ID), the release's version and our leaf certificate (SIGN_SHA1,
# pinned in ~/.config/notchcast/private.env by install-launchd.sh; never taken from the tooling copy),
# and only when nothing is installed yet, the release is newer, or the installed copy is not ours.
# It replaces only the bundle, keeping one previous app for rollback; settings and data are never touched.
# The in-app updater stays inert for app.notchcast (ReleaseChannel: development), so this is the update path.
# --install installs even with automatic updates off, e.g. to put one build on every maintainer machine.
# --pr=<n> installs PR n's newest green Test build run from main (test-build.yml) when it was built from the PR's current head, and
# holds it: later runs install nothing until --restore, which drops the hold and installs the newest snapshot or exits 1.
# Usage: update.sh [--install] [--retry] [--dry-run] [--pr=<n> | --restore] (any order)
# A newer release installs (and restarts a running app) at once, whether or not the Mac is in use.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.local/bin"

DRY=0
INSTALL=0
RETRY=0
PR=''
RESTORE=0
usage() { echo "Usage: update.sh [--install] [--retry] [--dry-run] [--pr=<n> | --restore] (any order)" >&2; exit 2; }
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY=1 ;;
        --install) INSTALL=1 ;;
        --retry) RETRY=1 ;;
        --pr=*) PR="${arg#--pr=}"; [[ "$PR" =~ ^[1-9][0-9]*$ ]] || usage; INSTALL=1 ;;
        --restore) RESTORE=1; INSTALL=1 ;;
        *) usage ;;
    esac
done
[ -z "$PR" ] || [ "$RESTORE" = 0 ] || usage
HERE="$(cd "$(dirname "$0")" && pwd -P)"
# shellcheck disable=SC1091
source "$HERE/config.env"
APP="${NOTCHCAST_APP:-/Applications/$APP_NAME.app}"
log() { printf '%s %s\n' "$(date +%Y-%m-%dT%H:%M:%S%z)" "$*"; }

plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist" 2>/dev/null || true; }

# The sync reports through issues on the fork (notchcast/ci.py): notchcast-sync, -main and -release are failures, one
# open issue per kind whose cause marker changes only with a new cause; notchcast-design issues stay open as the to-do.
# Only where ~/.config/notchcast/private.env defines notchcast_notify (notchcast/README.md, "Private hooks"), so one
# Mac acts: it is told once per issue and cause.
SIGN_SHA1=''
if [ -f "$HOME/.config/notchcast/private.env" ]; then
    # shellcheck disable=SC1091
    source "$HOME/.config/notchcast/private.env"
fi
if ! [[ "$SIGN_SHA1" =~ ^[0-9A-F]{40}$ ]]; then
    log "no SIGN_SHA1 (40 uppercase hex digits) in ~/.config/notchcast/private.env; refusing to install anything."
    log "Run notchcast/install-launchd.sh from a checkout to pin it, or add the line SIGN_SHA1=<leaf SHA-1> by hand."
    exit 1
fi
# One call: the bundle's seal and its leaf certificate (SHA-1 pin, as codesign's requirement language hashes it).
signed_by_us() { codesign --verify --deep --strict -R="certificate leaf = H\"$SIGN_SHA1\"" "$1" 2>/dev/null; }
alert_issues() {
    declare -F notchcast_notify >/dev/null || return 0
    local seen="$HOME/Library/Application Support/notchcast/alerted-issues" issues key n
    mkdir -p "$(dirname "$seen")"; touch "$seen"
    issues="$(gh issue list -R "$FORK_REPO" --state open --limit 50 --json number,title,url,body,labels \
        --jq '.[] | select(any(.labels[]; .name == "notchcast-sync" or .name == "notchcast-main" or .name == "notchcast-release"))
              | [(.number|tostring) + ":" + ((.body | capture("<!-- cause: (?<c>.*) -->").c) // .title), .title, .url] | @tsv')"
    while IFS=$'\t' read -r key title url; do
        [ -n "$key" ] && ! grep -qxF "$key" "$seen" || continue
        if [ "$DRY" = 1 ]; then log "would alert: $title"; continue; fi
        printf 'Notchcast: %s. Nothing was pushed or published. %s\n' "$title" "$url" | notchcast_notify \
            || { log "notify for $title failed; retried next run"; return 1; }
        echo "$key" >> "$seen"
        log "notified: $title"
    done <<< "$issues"
}
alert_issues || log "issue check failed; retried next run"

# The app's own "Automatically check for updates" toggle (Settings > General) governs this updater too: off means no
# update is installed unless --install is passed. A missing key or file means on; a first install is not an update.
SETTINGS="$HOME/.config/$BUNDLE_ID/settings.json"
if [ "$INSTALL" = 0 ] && [ -d "$APP" ] && [ "$(jq -r '.general.automaticallyCheckForUpdates' "$SETTINGS" 2>/dev/null)" = false ]; then
    log "automatic updates are off in $APP_NAME settings (general.automaticallyCheckForUpdates in $SETTINGS); not installing"
    exit 0
fi

INSTALLED="" OURS=0
if [ -d "$APP" ]; then
    [ "$(plist "$APP" CFBundleIdentifier)" = "$BUNDLE_ID" ] || { log "$APP is not $BUNDLE_ID; not touching it"; exit 0; }
    INSTALLED="$(plist "$APP" CFBundleShortVersionString)"
    signed_by_us "$APP" && OURS=1
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/notchcast-update.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
# Unpacks a downloaded zip to NEW and refuses anything but our leaf, bundle id and the version $2.
unpack() {
    mkdir "$WORK/x"
    ditto -x -k "$1" "$WORK/x"
    NEW="$(find "$WORK/x" -maxdepth 1 -name '*.app' | head -1)"
    [ -n "$NEW" ] || { log "no app in the release zip"; exit 1; }
    xattr -dr com.apple.quarantine "$NEW" 2>/dev/null || true
    signed_by_us "$NEW" || { log "not signed by $SIGN_IDENTITY ($SIGN_SHA1) or the seal is broken; refusing"; exit 1; }
    [ "$(plist "$NEW" CFBundleIdentifier)" = "$BUNDLE_ID" ] || { log "bundle id mismatch; refusing"; exit 1; }
    [ "$(plist "$NEW" CFBundleShortVersionString)" = "$2" ] || { log "version mismatch; refusing"; exit 1; }
}

HELD="$HOME/Library/Application Support/notchcast/test-build"
DISPATCH="gh workflow run test-build.yml -R $FORK_REPO --ref main -f pr=$PR"
if [ -n "$PR" ]; then
    RUN="$(gh run list -R "$FORK_REPO" -w test-build.yml -b main -s success -L 100 --json databaseId,displayTitle \
        --jq "[.[] | select(.displayTitle == \"Test build #$PR\")][0].databaseId // empty")"
    [ -n "$RUN" ] || { log "no green Test build #$PR; start one with: $DISPATCH"; exit 1; }
    HEAD="$(gh pr view "$PR" -R "$FORK_REPO" --json headRefOid --jq .headRefOid)"
    gh run download "$RUN" -R "$FORK_REPO" -n test-build -D "$WORK" \
        || { log "run $RUN has no test-build artifact (it expires after 3 days; a PR with no app change has none)"; exit 1; }
    ZIP="$(find "$WORK" -maxdepth 1 -name "$APP_NAME-*.zip" | head -1)"
    [ -n "$ZIP" ] || { log "no $APP_NAME zip in run $RUN's artifact"; exit 1; }
    WANT="${ZIP##*/"$APP_NAME"-}" && WANT="${WANT%.zip}"
    if [[ ! "$HEAD" =~ ^[0-9a-f]{40}$ ]] || [[ "$WANT" != *".pr$PR.${HEAD:0:8}" ]]; then
        log "Test build $WANT is not PR #$PR's current head ${HEAD:0:8}; refusing. Start a new one with: $DISPATCH"
        exit 1
    fi
    unpack "$ZIP" "$WANT"
    if [ "$DRY" = 1 ]; then log "would install test build $WANT over ${INSTALLED:-nothing}"; exit 0; fi
    STATUS=0
    "$HERE/install-app.sh" "$NEW" || STATUS=$?
    if [ "$STATUS" = 75 ]; then log "another install is running; nothing changed"; exit 0; fi
    [ "$STATUS" = 0 ] || exit 1
    mkdir -p "$(dirname "$HELD")"
    echo "$WANT" > "$HELD"
    log "holding test build $WANT; update.sh --restore goes back to the newest snapshot"
    exit 0
fi
if [ "$RESTORE" = 1 ]; then
    [ "$DRY" = 1 ] || rm -f "$HELD"
elif [ -n "$INSTALLED" ] && [ "$(cat "$HELD" 2>/dev/null)" = "$INSTALLED" ]; then
    log "test build $INSTALLED is held; nothing installed. Run update.sh --restore to go back to snapshots"
    exit 0
fi

SNAPSHOT='def snapshot: capture("^v?[0-9]+[.][0-9]+[.][0-9]+(-[a-z]+[.][0-9]+)?[.]snapshot[.](?<stamp>[0-9]{14})$").stamp // "";'
TAG="$(gh release list -R "$FORK_REPO" -L 1000 --json tagName,isDraft \
    --jq "$SNAPSHOT [.[] | select(.isDraft | not) | select(.tagName | startswith(\"v\")) | select((.tagName | snapshot) != \"\")]
          | sort_by(.tagName | snapshot) | last | .tagName // empty")"
# --restore either ends on the newest snapshot or exits 1, so a tester never takes a kept test build for main.
restore_failed() { [ "$RESTORE" = 0 ] || { log "--restore failed: ${INSTALLED:-nothing} is still installed"; exit 1; }; }
[ -n "$TAG" ] || { log "no $FORK_REPO snapshot yet"; restore_failed; exit 0; }
WANT="${TAG#v}"
CMP="$(jq -nr --arg want "$WANT" --arg have "$INSTALLED" "$SNAPSHOT"' if ($want|snapshot) > ($have|snapshot) then "newer" elif ($want|snapshot) == ($have|snapshot) then "same" else "older" end')"
if [ "$CMP" = older ] || { [ "$CMP" = same ] && [ "$OURS" = 1 ]; }; then
    log "nothing to install: newest snapshot $WANT, installed $INSTALLED ($([ "$OURS" = 1 ] && echo ours || echo "not ours"))"
    exit 0
fi
# A release that failed its stay-alive check is not installed again until someone passes --retry.
REFUSED="$HOME/Library/Application Support/notchcast/refused-release"
if [ "$RETRY" = 0 ] && [ "$(cat "$REFUSED" 2>/dev/null)" = "$WANT" ]; then
    log "$WANT did not stay alive at its last install; run update.sh $([ "$RESTORE" = 1 ] && echo '--restore ')--retry to try it again"
    restore_failed
    exit 0
fi
log "preparing $TAG over ${INSTALLED:-nothing} ($([ "$OURS" = 1 ] && echo ours || echo "not ours"))"
[ "$DRY" = 1 ] && exit 0

gh release download "$TAG" -R "$FORK_REPO" -D "$WORK" -p "$APP_NAME-${WANT}.zip"
unpack "$WORK/$APP_NAME-${WANT}.zip" "$WANT"

STATUS=0
"$HERE/install-app.sh" "$NEW" || STATUS=$?
if [ "$STATUS" = 75 ]; then log "another install is running; nothing changed"; restore_failed; exit 0; fi
if [ "$STATUS" != 0 ]; then
    mkdir -p "$(dirname "$REFUSED")"
    echo "$WANT" > "$REFUSED"
    exit 1
fi
rm -f "$REFUSED"
