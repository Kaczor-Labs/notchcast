#!/bin/bash
# Fetches upstream's main into refs/remotes/upstream/main of the repository in the current directory.
# Arguments are git fetch options (--no-tags).
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/config.env"
# Each try is capped (perl's alarm survives exec) and retried once: a stalled fetch ate a step.
limit=${NOTCHCAST_FETCH_TIMEOUT:-90}
fetch() { perl -e 'alarm shift; exec @ARGV or die "exec: $!"' "$limit" git fetch -q "$@" "https://github.com/$UPSTREAM_REPO.git" "+refs/heads/main:refs/remotes/upstream/main"; }
fetch "$@" && exit 0
echo "fetch-upstream: the fetch failed or passed ${limit}s; trying once more" >&2
fetch "$@"
