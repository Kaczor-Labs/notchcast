#!/bin/bash
# fetch-upstream.sh caps each try and retries once; git is a stub that hangs on the tries HANG names.
set -euo pipefail
root=$(git rev-parse --show-toplevel)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir "$scratch/bin"
cat > "$scratch/bin/git" <<'STUB'
#!/bin/bash
echo try >> "$TRIES"
# exec, so the alarm's SIGALRM ends the sleep itself and no child outlives the try.
[[ " $HANG " != *" $(wc -l < "$TRIES" | tr -d ' ') "* ]] || exec sleep 30
exit 0
STUB
chmod +x "$scratch/bin/git"
export PATH="$scratch/bin:$PATH" TRIES="$scratch/tries" NOTCHCAST_FETCH_TIMEOUT=1
# Real time is the contract under test (an OS alarm); each case waits at most 2 s.
run() { : > "$TRIES"; status=0; HANG=$1 bash "$root/notchcast/fetch-upstream.sh" --no-tags > "$scratch/out" 2>&1 || status=$?; }
run ''
[ "$status" -eq 0 ] && [ "$(wc -l < "$TRIES")" -eq 1 ] || { cat "$scratch/out"; echo 'FAIL: a fetch that works tried more than once'; exit 1; }
run 1
[ "$status" -eq 0 ] && [ "$(wc -l < "$TRIES")" -eq 2 ] && grep -q 'trying once more' "$scratch/out" \
    || { cat "$scratch/out"; echo 'FAIL: a stalled first fetch was not cut and retried'; exit 1; }
echo 'PASS: a stalled fetch is cut at its cap and retried once'
run '1 2'
[ "$status" -ne 0 ] && [ "$(wc -l < "$TRIES")" -eq 2 ] || { cat "$scratch/out"; echo 'FAIL: two stalled fetches did not fail after one retry'; exit 1; }
echo 'PASS: two stalled fetches fail after one retry'
