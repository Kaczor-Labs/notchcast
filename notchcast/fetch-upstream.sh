#!/bin/bash
# Fetches upstream's main into refs/remotes/upstream/main of the repository in the current directory.
# Arguments are git fetch options (--no-tags).
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/config.env"
limit=${NOTCHCAST_FETCH_TIMEOUT:-90}
# Its own process group, killed whole at the cap: git's https helper holds the socket and our stdout.
capped() {
    perl -e 'my $limit = shift; my $pid = fork // die "fork: $!";
        if (!$pid) { setpgrp(0, 0); exec @ARGV or die "exec: $!" }
        setpgrp($pid, $pid);
        $SIG{ALRM} = sub { kill "KILL", -$pid; waitpid($pid, 0); exit 124 };
        alarm $limit; waitpid($pid, 0); kill "KILL", -$pid;
        exit($? & 127 ? 128 + ($? & 127) : $? >> 8)' "$limit" "$@"
}
fetch() { capped git fetch -q "$@" "https://github.com/$UPSTREAM_REPO.git" "+refs/heads/main:refs/remotes/upstream/main"; }
fetch "$@" && exit 0
echo "fetch-upstream: the fetch failed or passed ${limit}s; trying once more" >&2
fetch "$@"
