#!/bin/bash
# Install Notchcast for this user. Usage: install-launchd.sh all|update|kick|prune|queue [--auto-install]
#   all     first install: update.sh installs /Applications/Notchcast.app, migrate.sh copies the old Tinycast data once,
#           the old Tinycast .app goes to the Trash (its data stays), then update and kick below are loaded.
#   update  notchcast.update runs update.sh every 30 min (needs gh logged in).
#   kick    notchcast.kick runs kick.sh every 10 min: starts the sync when upstream moved (needs gh).
#   prune   notchcast.prune prunes merged branches on Sundays at 04:00 (notchcast/docs/branch-cleanup.md).
#   queue   notchcast.queue runs queue.sh every 3 min: the one landing queue, on one Mac only (README).
# Every mode first copies the committed notchcast/ of this checkout to the tooling copy the jobs run, and
# then pins SIGN_SHA1 from that commit in private.env when absent. Rerun it to update the tooling (#872).
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
    *) echo "usage: $0 all|update|kick|prune|queue [--auto-install]" >&2; exit 2 ;;
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

# The main checkout, never a linked worktree that may go away.
main_checkout() {
    dirname "$(git -C "$HERE" rev-parse --path-format=absolute --git-common-dir)"
}

TOOLS="$HOME/Library/Application Support/notchcast/tools"
JOBS="$HOME/Library/Application Support/notchcast/jobs"
TOOLS_NEEDS='update.sh install-app.sh config.env kick.sh ci.py prune-branches.py'

# Jobs run only this copy, made here from the checkout's HEAD; nothing refreshes it from origin (#872).
install_tools() {
    [ -z "${TOOLS_INSTALLED:-}" ] || return 0
    local repo rev stage old f
    repo=$(git -C "$HERE" rev-parse --show-toplevel)
    rev=$(git -C "$repo" rev-parse --verify 'HEAD^{commit}')
    [ -z "$(git -C "$repo" status --porcelain -- notchcast)" ] \
        || echo "notchcast/ has uncommitted changes; installing the tooling of HEAD ${rev:0:12} without them" >&2
    mkdir -p "$(dirname "$TOOLS")"
    stage=$(mktemp -d "$TOOLS.XXXXXX")
    # A file, not a pipe: tar exits at the end marker, and git archive then dies of SIGPIPE.
    git -C "$repo" archive -o "$stage/tools.tar" "$rev" notchcast/
    tar -xf "$stage/tools.tar" -C "$stage"
    rm -f "$stage/tools.tar"
    for f in $TOOLS_NEEDS; do
        [ -f "$stage/notchcast/$f" ] || { rm -rf "$stage"; echo "HEAD ${rev:0:12} lacks notchcast/$f" >&2; exit 1; }
    done
    git -C "$repo" log -1 --format='%H %cI' "$rev" > "$stage/notchcast/.commit"
    old=$(readlink "$TOOLS" || true)
    ln -s "$stage/notchcast" "$stage/link"
    mv -fh "$stage/link" "$TOOLS"
    TOOLS_DIR="$stage/notchcast"
    for f in 'Notchcast update' 'Notchcast sync check'; do
        f="$JOBS/$f"
        [ "$(sed -n 2p "$f" 2>/dev/null | cut -c1-6)" = tools= ] || continue
        { printf '#!/bin/bash\ntools=%q\n' "$TOOLS_DIR"; tail -n +3 "$f"; } > "$f.new"
        chmod 755 "$f.new"
        mv -f "$f.new" "$f"
    done
    # Keep the previous copy for a job still running from it; older copies and the old kick copy go.
    for f in "$TOOLS".??????; do
        [ "$f" = "$stage" ] || [ "$f/notchcast" = "$old" ] || rm -rf "$f"
    done
    local kick="${TOOLS%/tools}/kick-tools"
    if [ -L "$kick" ]; then
        old=$(readlink "$kick")
        rm -f "$kick"
        case "$old" in "$kick".??????/notchcast) rm -rf "${old%/notchcast}" ;; esac
    fi
    TOOLS_INSTALLED=1
    TOOLS_REV=$rev
    echo "installed tooling from ${rev:0:12} at $TOOLS"
}

# update.sh trusts only this machine's pin, never one in the checkout or the tooling copy.
install_pin() {
    local env="$HOME/.config/notchcast/private.env" sha
    if [ -f "$env" ] && grep -qE '^[[:space:]]*(export[[:space:]]+)?SIGN_SHA1=' "$env"; then return 0; fi
    sha=$(git -C "$HERE" show "$TOOLS_REV:notchcast/config.env" | sed -n 's/^RELEASE_SIGN_SHA1=//p')
    [[ "$sha" =~ ^[0-9A-F]{40}$ ]] \
        || { echo "HEAD ${TOOLS_REV:0:12} has no valid RELEASE_SIGN_SHA1; SIGN_SHA1 not pinned" >&2; exit 1; }
    mkdir -p "$(dirname "$env")"
    if [ -s "$env" ] && [ -n "$(tail -c 1 "$env")" ]; then echo >> "$env"; fi
    printf 'SIGN_SHA1=%s\n' "$sha" >> "$env"
    echo "pinned SIGN_SHA1 in $env"
}

# Login Items shows the executable, so a job runs through a named wrapper rather than /bin/bash.
named_job() { # name program...
    local name=$1
    local wrapper="$JOBS/$1"; shift
    mkdir -p "$JOBS"
    printf '#!/bin/bash\n' > "$wrapper"
    case "$name" in
        'Notchcast update'|'Notchcast sync check')
            local script=${2##*/} args=''
            shift 2
            if [ "$#" -gt 0 ]; then args="$(printf '%q ' "$@")"; fi
            # The copy's real folder, so a running job never reads a sibling through a swapped link.
            printf 'tools=%q\n' "$TOOLS_DIR" >> "$wrapper"
            printf 'if [ -f "$tools/%s" ]; then exec /bin/bash "$tools/%s" %s; fi\n' \
                "$script" "$script" "$args" >> "$wrapper"
            printf "echo 'no installed tooling; run notchcast/install-launchd.sh from a checkout'\nexit 1\n" >> "$wrapper"
            ;;
        *) printf 'exec %s\n' "$(printf '%q ' "$@")" >> "$wrapper" ;;
    esac
    chmod 755 "$wrapper"
    /bin/bash -n "$wrapper"
    echo "$wrapper"
}

install_update() {
    agent notchcast.update update \
        '<key>StartInterval</key><integer>1800</integer>
<key>ProcessType</key><string>Background</string>
<key>EnvironmentVariables</key><dict><key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string></dict>' \
        "$(named_job 'Notchcast update' /bin/bash "$TOOLS/update.sh" ${UPDATE_ARG:+"$UPDATE_ARG"})"
}

install_kick() {
    agent notchcast.kick kick \
        '<key>StartInterval</key><integer>600</integer>
<key>ProcessType</key><string>Background</string>
<key>EnvironmentVariables</key><dict><key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string></dict>' \
        "$(named_job 'Notchcast sync check' /bin/bash "$TOOLS/kick.sh")"
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
    # Runs in the main checkout, from the installed tooling copy.
    local repo
    repo=$(main_checkout)
    RUN_AT_LOAD=false agent notchcast.prune prune \
        '<key>StartCalendarInterval</key><dict><key>Weekday</key><integer>0</integer><key>Hour</key><integer>4</integer><key>Minute</key><integer>0</integer></dict>
<key>WorkingDirectory</key><string>'"$repo"'</string>
<key>EnvironmentVariables</key><dict><key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string></dict>' \
        "$(named_job 'Notchcast prune' /usr/bin/env python3 "$TOOLS/prune-branches.py" \
            --remote --local --log "$LOGS/pruned-branches.tsv" ${args[@]+"${args[@]}"})"
}

install_queue() {
    agent notchcast.queue queue \
        '<key>StartInterval</key><integer>180</integer>
<key>ProcessType</key><string>Background</string>
<key>EnvironmentVariables</key><dict><key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string></dict>' \
        "$(named_job 'Notchcast landing queue' /bin/bash "$TOOLS/queue.sh" "$(main_checkout)")"
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
    all|update|kick|prune|queue) install_tools; install_pin ;;
esac
case "${1:-}" in
    all) first_install; install_update; install_kick ;;
    update) install_update ;;
    kick) install_kick ;;
    prune) install_prune ;;
    queue) install_queue ;;
    *) echo "usage: $0 all|update|kick|prune|queue [--auto-install]" >&2; exit 2 ;;
esac
