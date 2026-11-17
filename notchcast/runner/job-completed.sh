#!/bin/bash
# Runner hook: a job's build products never outlive it on a maintainer Mac; the harness cache stays, capped.
# An lsregister left hanging on this job's products dies with the job; other lsregister runs are left alone.
pgrep -f lsregister | while read -r pid; do
    case "$(ps -o args= -p "$pid")" in *"lsregister "*" ${RUNNER_TEMP:?}/"*) kill -KILL "$pid" ;; esac
done
rm -rf "${RUNNER_TEMP:?}/DerivedData"
case "${TMPDIR:-}" in
    */gh-runner/*/tmp)
        find "$TMPDIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
        find "${TMPDIR%/tmp}/_diag" -type f -mtime +2 -delete 2>/dev/null
        ;;
esac
CACHE_CAP_MB=1500
cache="${RUNNER_TOOL_CACHE:-$(dirname "$RUNNER_TEMP")/_tool}/swiftc-cache"
[ -d "$cache" ] || exit 0
# swiftc-cache.py finish prunes by the keys in <name>.log, so a log kept across jobs keeps every key forever.
for log in "$cache"/*.log; do
    [ -f "$log" ] || continue
    [ ! -d "${log%.log}" ] || touch "${log%.log}"
    rm -f "$log"
done
find "$cache" -mindepth 1 -maxdepth 1 -type d -mtime +3 -exec rm -rf {} +
while [ "$(du -sm "$cache" | cut -f1)" -gt "$CACHE_CAP_MB" ]; do
    oldest=$(find "$cache" -mindepth 1 -maxdepth 1 -exec stat -f '%m %N' {} + | sort -n | head -1 | cut -d' ' -f2-)
    [ -n "$oldest" ] || break
    rm -rf "$oldest"
done
exit 0
