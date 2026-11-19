# Sourced by upstream's runner so fork harnesses never need another shared registration.
# Harness suites leak plists into ~/Library/Preferences; the run removes what it created, pass or fail.
if [ "$emit_db" -eq 0 ]; then
    python3 notchcast/pref-sweep.py begin $$ || true
    trap 'python3 notchcast/pref-sweep.py end $$ || true' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM HUP
fi
harness_inputs=$(python3 notchcast/harness_inputs.py) || {
    echo '::error::Fork harness input resolution failed; refusing an incomplete test suite' >&2
    exit 1
}
while IFS=$'\t' read -r harness has_header sources; do
    [ -e "$harness" ] || continue
    name=$(basename "$harness" .swift)
    if [ "$has_header" -eq 1 ]; then
        if [[ "$name" != nc-* && "$name" != notchcast-* ]]; then
            if [ "$emit_db" -eq 1 ]; then
                if node - "$DB" "$PWD/$harness" $sources <<'JS'
const fs = require("node:fs");
const path = require("node:path");
const [file, harness, ...sources] = process.argv.slice(2);
const entries = JSON.parse(fs.readFileSync(file, "utf8") + "]");
const entry = entries.find((item) => item.files.includes(harness));
if (!entry) process.exit(1);
entry.command += " " + sources.map((source) => path.resolve(source)).join(" ");
fs.writeFileSync(file, JSON.stringify(entries).slice(0, -1));
JS
                then continue; fi
            else
                found=0
                extra_sources=$(printf '%s ' $sources)
                extra_sources=${extra_sources% }
                for queue_file in "$QUEUE" ${EXCLUSIVE_QUEUE:+"$EXCLUSIVE_QUEUE"}; do # upstream dropped it in ff4fa05
                    if awk -v name="$name" '$2 == name { found=1 } END { exit !found }' "$queue_file"; then
                        awk -v name="$name" -v extras="$extra_sources" \
                            '$2 == name { $0 = $0 " " extras } { print }' "$queue_file" > "$queue_file.sources"
                        mv "$queue_file.sources" "$queue_file"
                        found=1
                    fi
                done
                [ "$found" -eq 0 ] || continue
            fi
        fi
        run "$name" $sources
    elif [[ "$name" == nc-* ]]; then
        run "$name" $sources
    elif grep -q "^run $name " "$SELF"; then
        continue
    else
        # Compiles alone and fails as one harness; the rest of the suite still runs.
        echo "::error::$harness needs a // notchcast-sources: header" >&2
        run "$name"
    fi
done <<< "$harness_inputs"
hidden_tests=$(sed -n 's/^HIDDEN_TESTS="\(.*\)"$/\1/p' notchcast/config.env)
# Anywhere but a Mac only the LINUX_OK_TESTS harnesses run; NOTCHCAST_PLATFORM lets a test play the other system.
linux_only=
case "${NOTCHCAST_PLATFORM:-$(uname -s)}" in
    Darwin) ;;
    *) linux_only=" $(sed -n 's/^LINUX_OK_TESTS="\(.*\)"$/\1/p' notchcast/config.env) " ;;
esac
hosted_only=$(sed -n 's/^HOSTED_ONLY_TESTS="\(.*\)"$/\1/p' notchcast/config.env)
hosted_why='hosted-only: it can reach the keychain, the app'"'"'s data, a permission prompt, a window or focus, so it runs only on a GitHub-hosted or isolated runner (HOSTED_ONLY_TESTS, notchcast/config.env)'
# An isolated runner says so in its own service environment; nothing in this repository may set that variable.
if [ "${RUNNER_ENVIRONMENT:-}" = github-hosted ] || [ "${NOTCHCAST_ISOLATED_RUNNER:-}" = 1 ]; then hosted_only=; fi
# A self-hosted runner names in its own .env the harnesses it cannot run; a hosted or isolated one proves trees.
runner_skip=
if [ "${RUNNER_ENVIRONMENT:-}" = self-hosted ] && [ "${NOTCHCAST_ISOLATED_RUNNER:-}" != 1 ]; then
    runner_skip=${NOTCHCAST_RUNNER_SKIP_TESTS:-}
fi
if [ "$emit_db" -eq 0 ] && [ -n "$only" ] && [[ " $hosted_only " == *" $only "* ]]; then
    echo "REFUSED: $only is $hosted_why" >&2
    exit 1
fi
# A whole suite drops hidden features' harnesses, then CI narrows it: a selection, the mac-only ones off a Mac, a
# name-hash shard "<index> <count>", then the runner's skips and, off a hosted or isolated runner, the hosted-only ones.
if [ "$emit_db" -eq 0 ] && [ -z "$only" ] && [ -n "$hidden_tests$hosted_only${NOTCHCAST_ONLY_TESTS:-}${CI_SKIP_TESTS:-}${NOTCHCAST_SHARD:-}$linux_only$runner_skip" ]; then
    awk -v only=" ${NOTCHCAST_ONLY_TESTS:-} " -v skip=" ${CI_SKIP_TESTS:-} " -v shard="${NOTCHCAST_SHARD:-0 1}" \
        -v runner_skip=" $runner_skip " \
        -v hidden=" $hidden_tests " -v linux="$linux_only" -v hosted=" $hosted_only " -v why="$hosted_why" '
        BEGIN { split(shard, part, " "); alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.+" }
        index(hidden, " " $2 " ") { dropped++; next }
        only !~ /^ *$/ && !index(only, " " $2 " ") { next }
        linux != "" && !index(linux, " " $2 " ") { mac_only = mac_only " " $2; macs++; next }
        { held = index(hosted, " " $2 " "); skipped = index(skip, " " $2 " "); unfit = index(runner_skip, " " $2 " ") }
        { total += !held && !skipped && !unfit }
        { hash = 0; for (i = 1; i <= length($2); i++) hash = (hash * 31 + index(alphabet, substr($2, i, 1))) % 1000003 }
        hash % part[2] != part[1] { next }
        held { print "SKIPPED " $2 ": " why > "/dev/stderr"; next }
        skipped { print "skipped on the runner: " $2 > "/dev/stderr"; next }
        unfit { print "::notice::SKIPPED on this runner: " $2 > "/dev/stderr"; next }
        { kept++; print }
        END {
            if (dropped) print dropped " hidden-feature harnesses not run (HIDDEN_TESTS, notchcast/config.env)" > "/dev/stderr"
            if (macs) print macs " mac-only harnesses skipped on Linux (not in LINUX_OK_TESTS, notchcast/config.env):" mac_only > "/dev/stderr"
            if (part[2] > 1) print "shard " part[1] " of " part[2] ": " kept + 0 " of " total + 0 " harnesses" > "/dev/stderr"
        }
        ' "$QUEUE" > "$QUEUE.kept" || exit 1
    mv "$QUEUE.kept" "$QUEUE"
    ran=$(($(wc -l < "$QUEUE")))
    if [ "$ran" -eq 0 ] && [ -n "$linux_only" ]; then
        echo 'No linux-ok harness to run here; the mac-only ones above run on a Mac.'
        exit 0
    fi
fi
