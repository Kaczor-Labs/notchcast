#!/bin/bash
# Runner hook: a job's build products never outlive it on a maintainer Mac. The compiled-harness cache stays.
# An lsregister left hanging on this job's products dies with the job; other lsregister runs are left alone.
pgrep -f lsregister | while read -r pid; do
    case "$(ps -o args= -p "$pid")" in *"lsregister "*" ${RUNNER_TEMP:?}/"*) kill -KILL "$pid" ;; esac
done
rm -rf "${RUNNER_TEMP:?}/DerivedData"
case "${TMPDIR:-}" in
    */gh-runner/*/tmp) find "$TMPDIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} + ;;
esac
exit 0
