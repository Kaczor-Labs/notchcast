#!/bin/bash
# One tick of the landing queue (LaunchAgent notchcast.queue, install-launchd.sh queue): under the land lease, main's
# train.sh --queue lands what is signed off. Usage: queue.sh <checkout>. README, "The landing queue".
set -euo pipefail
[ "$#" -eq 1 ] || { echo 'usage: queue.sh <checkout>' >&2; exit 2; }
[ ! -f "$HOME/.config/notchcast/private.env" ] || source "$HOME/.config/notchcast/private.env"
[ -n "${NOTCHCAST_LAND_LOCK:-}" ] || { echo 'queue: no NOTCHCAST_LAND_LOCK in private.env, so no lease to land under' >&2; exit 1; }
cd "$1"
echo "queue: tick $(date '+%Y-%m-%d %H:%M:%S %Z')"
# Fixed per machine, so a killed or rebooted queue takes its own lease back at the next tick.
holder="queue@$(hostname -s)"
if ! taken=$($NOTCHCAST_LAND_LOCK take "$holder" 2>&1); then
    echo "$taken"
    [[ "$taken" != *' is held by '* ]] || { echo 'queue: the land lease is held; next tick'; exit 0; }
    echo 'queue: could not take the land lease' >&2
    exit 1
fi
scratch=$(mktemp -d)
release() {
    $NOTCHCAST_LAND_LOCK drop "$holder" || echo 'WARN: could not drop the land lease; it expires by itself' >&2
    git worktree remove --force "$scratch/tree" >/dev/null 2>&1 || true
    rm -rf "$scratch"
}
trap release EXIT
trap 'exit 1' HUP INT TERM
git fetch -q origin main
git worktree add --quiet --detach "$scratch/tree" origin/main
cd "$scratch/tree"
# In the background: bash runs a trap only between foreground commands, and the train must get the stop to scrap.
NOTCHCAST_LAND_LEASE=$holder bash notchcast/train.sh --queue &
train=$!
trap 'kill -TERM "$train" 2>/dev/null; wait "$train"; exit 143' HUP INT TERM
wait "$train"
