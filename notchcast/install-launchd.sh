#!/bin/bash
# Install Notchcast for this user. Usage: install-launchd.sh all|update|kick|prune [--auto-install]
#   all     first install: update.sh installs /Applications/Notchcast.app, migrate.sh copies the old Tinycast data once,
#           the old Tinycast .app goes to the Trash (its data stays), then update and kick below are loaded.
#   update  notchcast.update runs notchcast/update.sh every 30 min (needs gh logged in).
#   kick    notchcast.kick runs kick.sh from origin/main every 10 min: starts the sync when upstream moved (needs gh).
#   prune   notchcast.prune prunes merged branches on Sundays at 04:00 (notchcast/docs/branch-cleanup.md).
# No agent runs the app: it starts at login through its own "Launch at login" setting (SMAppService).
# Builds and releases run on GitHub Actions (.github/workflows/sync.yml), not on a Mac.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/config.env"
APP="${NOTCHCAST_APP:-/Applications/$APP_NAME.app}"
LOGS="$HOME/Library/Logs/notchcast"
DOMAIN="gui/$(id -u)"
UPDATE_ARG=""
case "${2:-}" in
    --auto-install) UPDATE_ARG=--install ;;
    "") ;;
    *) echo "usage: $0 all|update|kick|prune [--auto-install]" >&2; exit 2 ;;
esac
[ "$#" -le 2 ] || { echo "too many arguments" >&2; exit 2; }
mkdir -p "$LOGS" "$HOME/Library/LaunchAgents"

agent() { # label log-name extra-plist-keys program...
    local label=$1 name=$2 extra=$3; shift 3
    local plist="$HOME/Library/LaunchAgents/$label.plist" args=""
    for a in "$@"; do args="$args<string>$a</string>"; done
    cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$label</string>
<key>ProgramArguments</key><array>$args</array>
<key>RunAtLoad</key><${RUN_AT_LOAD:-true}/>
$extra
<key>StandardOutPath</key><string>$LOGS/$name.log</string>
<key>StandardErrorPath</key><string>$LOGS/$name.log</string>
</dict></plist>
PLIST
    plutil -lint -s "$plist"
    launchctl bootout "$DOMAIN/$label" 2>/dev/null || true
    launchctl bootstrap "$DOMAIN" "$plist"
    echo "loaded $label -> $LOGS/$name.log"
}

# Login Items shows the executable, so a job runs through a named wrapper rather than /bin/bash.
named_job() { # name program...
    local name=$1 copy='' needs=''
    local wrapper="$HOME/Library/Application Support/notchcast/jobs/$1"; shift
    case "$name" in
        'Notchcast update') copy=tools needs='update.sh install-app.sh config.env' ;;
        # Its own copy: refreshing the update copy would delete the tree a running update.sh reads.
        'Notchcast sync check') copy=kick-tools needs='kick.sh ci.py config.env' ;;
    esac
    mkdir -p "$(dirname "$wrapper")"
    printf '#!/bin/bash\n' > "$wrapper"
    if [ -n "$copy" ]; then
        printf 'repo=%q copy=%q needs=%q\n' "$HERE/.." "$copy" "$needs" >> "$wrapper"
        cat >> "$wrapper" <<'REFRESH'
set -o pipefail
root="$HOME/Library/Application Support/notchcast"
tools="$root/$copy"
stage=''
refresh() {
    git -C "$repo" fetch --quiet origin main 2>/dev/null || return 1
    stage=$(mktemp -d "$tools.XXXXXX") || return 1
    # A file, not a pipe: tar exits at the end marker, and git archive then dies of SIGPIPE.
    git -C "$repo" archive -o "$stage/tools.tar" refs/remotes/origin/main notchcast/ 2>/dev/null || return 1
    tar -xf "$stage/tools.tar" -C "$stage" 2>/dev/null || return 1
    rm -f "$stage/tools.tar"
    local old f
    for f in $needs; do [ -f "$stage/notchcast/$f" ] || return 1; done
    old=$(readlink "$tools")
    ln -s "$stage/notchcast" "$stage/link" && mv -fh "$stage/link" "$tools" || return 1
    stage=''
    case "$old" in "$tools".??????/notchcast) rm -rf "${old%/notchcast}" ;; esac
}
if ! refresh; then
    echo 'tooling refresh failed; using previous code'
    [ -z "$stage" ] || rm -rf "$stage"
fi
REFRESH
        local script=${2##*/} args=''
        shift 2
        if [ "$#" -gt 0 ]; then args="$(printf '%q ' "$@")"; fi
        printf 'if [ -f "$tools/%s" ]; then exec /bin/bash "$tools/%s" %s; fi\n' \
            "$script" "$script" "$args" >> "$wrapper"
        set -- /bin/bash "$HERE/$script" "$@"
    fi
    if [ "$copy" = kick-tools ]; then
        printf "echo 'no copy of origin/main yet; the sync check never runs the checkout'\nexit 1\n" >> "$wrapper"
    else
        printf 'exec %s\n' "$(printf '%q ' "$@")" >> "$wrapper"
    fi
    chmod 755 "$wrapper"
    /bin/bash -n "$wrapper"
    echo "$wrapper"
}

install_update() {
    agent notchcast.update update \
        '<key>StartInterval</key><integer>1800</integer>
<key>ProcessType</key><string>Background</string>
<key>EnvironmentVariables</key><dict><key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string></dict>' \
        "$(named_job 'Notchcast update' /bin/bash "$HERE/update.sh" ${UPDATE_ARG:+"$UPDATE_ARG"})"
}

install_kick() {
    agent notchcast.kick kick \
        '<key>StartInterval</key><integer>600</integer>
<key>ProcessType</key><string>Background</string>
<key>EnvironmentVariables</key><dict><key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string></dict>' \
        "$(named_job 'Notchcast sync check' /bin/bash "$HERE/kick.sh")"
}

install_prune() {
    local roots=() root args=()
    if [ -f "$HOME/.config/notchcast/private.env" ]; then
        source "$HOME/.config/notchcast/private.env"
    fi
    IFS=: read -r -a roots <<< "${NOTCHCAST_WORKTREE_ROOTS:-}"
    for root in ${roots[@]+"${roots[@]}"}; do
        [ -z "$root" ] || args+=(--worktree-root "$root")
    done
    # Main checkout, never a worktree that may go away; the copy notchcast.update refreshes.
    local repo
    repo=$(dirname "$(git -C "$HERE" rev-parse --path-format=absolute --git-common-dir)")
    RUN_AT_LOAD=false agent notchcast.prune prune \
        '<key>StartCalendarInterval</key><dict><key>Weekday</key><integer>0</integer><key>Hour</key><integer>4</integer><key>Minute</key><integer>0</integer></dict>
<key>WorkingDirectory</key><string>'"$repo"'</string>
<key>EnvironmentVariables</key><dict><key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string></dict>' \
        "$(named_job 'Notchcast prune' /usr/bin/env python3 "$HOME/Library/Application Support/notchcast/tools/prune-branches.py" \
            --remote --local --log "$LOGS/pruned-branches.tsv" ${args[@]+"${args[@]}"})"
}

first_install() {
    /bin/bash "$HERE/update.sh" ${UPDATE_ARG:+"$UPDATE_ARG"}
    [ -d "$APP" ] || { echo "no $APP after update.sh; see its output" >&2; exit 1; }
    /bin/bash "$HERE/migrate.sh"
    # The old app goes to the Trash, never rm; its preferences, data and Keychain items stay where they are.
    if [ -d "$OLD_APP" ]; then
        local trashed
        trashed="$HOME/.Trash/$(basename "$OLD_APP" .app) $(date +%Y%m%d-%H%M%S).app"
        mv "$OLD_APP" "$trashed"
        echo "old app moved to $trashed"
    fi
}

case "${1:-}" in
    all) first_install; install_update; install_kick ;;
    update) install_update ;;
    kick) install_kick ;;
    prune) install_prune ;;
    *) echo "usage: $0 all|update|kick|prune [--auto-install]" >&2; exit 2 ;;
esac
