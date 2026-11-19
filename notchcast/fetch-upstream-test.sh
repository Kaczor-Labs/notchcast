#!/bin/bash
# fetch-upstream.sh caps each try and retries once; git is a stub that hangs on the tries HANG names.
set -euo pipefail
root=$(git rev-parse --show-toplevel)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir "$scratch/bin"
# A hanging try leaves a child holding stdout, as git's https helper does; its pid goes to CHILDREN.
cat > "$scratch/bin/git" <<'STUB'
#!/bin/bash
echo try >> "$TRIES"
[[ " $HANG " == *" $(wc -l < "$TRIES" | tr -d ' ') "* ]] || exit 0
sleep 30 &
echo $! >> "$CHILDREN"
wait
STUB
chmod +x "$scratch/bin/git"
export PATH="$scratch/bin:$PATH" TRIES="$scratch/tries" CHILDREN="$scratch/children" NOTCHCAST_FETCH_TIMEOUT=1
# Read through a pipe, as an Actions step or $(...) does: it ends only when every holder of stdout is gone.
run() {
    : > "$TRIES"
    : > "$CHILDREN"
    status=0
    # The reader gives up after 5 s, so an orphan holding the pipe fails the case rather than stalling it.
    HANG=$1 bash "$root/notchcast/fetch-upstream.sh" --no-tags 2>&1 | perl -e 'alarm 5; exec "cat"' > "$scratch/out" || status=$?
}
alive() { local pid; for pid in $(cat "$CHILDREN"); do ps -o stat= -p "$pid" | grep -qv '^Z' && return 0; done; return 1; }
# Real time is the contract under test (an OS alarm): each case takes about 2 s, at most 5.
run ''
[ "$status" -eq 0 ] && [ "$(wc -l < "$TRIES")" -eq 1 ] || { cat "$scratch/out"; echo 'FAIL: a fetch that works tried more than once'; exit 1; }
run 1
! alive || { echo 'FAIL: a capped try left its child running'; exit 1; }
[ "$status" -eq 0 ] && [ "$(wc -l < "$TRIES")" -eq 2 ] && grep -q 'trying once more' "$scratch/out" \
    || { cat "$scratch/out"; echo 'FAIL: a stalled first fetch was not cut and retried'; exit 1; }
echo 'PASS: a stalled fetch is cut at its cap, its whole process group with it, and retried once'
run '1 2'
! alive || { echo 'FAIL: a capped try left its child running'; exit 1; }
[ "$status" -ne 0 ] && [ "$(wc -l < "$TRIES")" -eq 2 ] || { cat "$scratch/out"; echo 'FAIL: two stalled fetches did not fail after one retry'; exit 1; }
echo 'PASS: two stalled fetches fail after one retry'
# A cancelled caller (a stopped workflow step, Ctrl-C) signals the script's group; the fetch runs in its own group and must die with it.
: > "$TRIES"
: > "$CHILDREN"
HANG=1 NOTCHCAST_FETCH_TIMEOUT=20 perl -e 'setpgrp(0, 0); exec @ARGV' bash "$root/notchcast/fetch-upstream.sh" --no-tags > /dev/null 2>&1 &
caller=$!
perl -e 'for (1..100) { exit 0 if -s $ARGV[0]; select(undef, undef, undef, 0.05) } exit 1' "$CHILDREN" || { echo 'FAIL: the stub never started'; exit 1; }
kill -TERM -- "-$caller"
wait "$caller" 2>/dev/null || true
perl -e 'select(undef, undef, undef, 0.3)'
! alive || { echo 'FAIL: a cancelled fetch left its child running'; exit 1; }
echo 'PASS: a cancelled fetch takes its process group with it'
