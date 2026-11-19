#!/bin/bash
# config.env's lists (harness-tags.sh) and test-harnesses.sh's own scan must name the same harnesses.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
eval "$(sed -n '/^harness_list() {$/,/^}$/p' notchcast/test-harnesses.sh)"
for pair in HOSTED_ONLY_TESTS:hosted-only LINUX_OK_TESTS:linux-ok; do
    key=${pair%%:*} tag=${pair#*:}
    sourced=$(bash -c "source notchcast/config.env; echo \$$key" | tr ' ' '\n' | grep . | sort)
    scanned=$(harness_list "$key" "$tag" | tr ' ' '\n' | grep . | sort)
    grep -q '^nc-' <<< "$scanned" || { echo "FAIL: no tagged fork harness in $key"; exit 1; }
    [ "$sourced" = "$scanned" ] || { echo "FAIL: $key differs"; diff <(echo "$sourced") <(echo "$scanned"); exit 1; }
done
echo 'PASS: config.env and test-harnesses.sh read the same harness tags'
