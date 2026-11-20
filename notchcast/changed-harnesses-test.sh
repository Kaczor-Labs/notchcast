#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir "$scratch/bin"
cat > "$scratch/bin/git" <<'STUB'
#!/bin/bash
case "$1" in
    rev-parse) echo "$ROOT" ;;
    diff) printf '%s\0' $CHANGED ;;
esac
STUB
chmod +x "$scratch/bin/git"
export ROOT="$root" PATH="$scratch/bin:$PATH"
unset GITHUB_ACTIONS RUNNER_ENVIRONMENT
export CHANGED=Tinycast/Features/Notchcast/Hidden/NotchcastHidden.swift
bash "$root/notchcast/changed-harnesses.sh" base head > "$scratch/selected"
for name in DeepLinkTests SettingsHistoryTests; do
    grep -qx "$name" "$scratch/selected" || { echo "FAIL: $CHANGED omitted $name"; exit 1; }
done
# An empty path once matched an empty pattern and selected every harness, upstream ones included.
if grep -qx CalcTests "$scratch/selected"; then echo "FAIL: $CHANGED selected an unrelated upstream harness"; exit 1; fi
echo 'PASS: the hidden tab set selects every harness compiling SettingsTab'
# A harness with no extra sources must not match every change (printf of no arguments prints one empty line).
export CHANGED="Tinycast/Features/Todo/TodoModule.swift"
bash "$root/notchcast/changed-harnesses.sh" base head > "$scratch/selected"
if grep -qx CalcTests "$scratch/selected"; then echo 'FAIL: an unrelated change selected CalcTests'; exit 1; fi
echo 'PASS: unrelated upstream harnesses stay unselected'
export CHANGED=Tests/ClipboardTextTests.swift GITHUB_ACTIONS=true
for runner in local self-hosted github-hosted; do
    export RUNNER_ENVIRONMENT=$runner
    bash "$root/notchcast/changed-harnesses.sh" base head > "$scratch/selected"
    grep -qx ClipboardTextTests "$scratch/selected" || { echo "FAIL: selection on $runner omitted OCR"; exit 1; }
done
echo 'PASS: selection keeps VM-incompatible harnesses on every runner; the shard runner drops them on hosted VMs'

unset GITHUB_ACTIONS RUNNER_ENVIRONMENT
# pick <unsure file> <changed paths...>: the selection on stdout, the unsure reasons in the file.
pick() { local file=$1; shift; CHANGED="$*" bash "$root/notchcast/changed-harnesses.sh" --unsure "$file" base head; }
pick "$scratch/unsure" Tinycast/Features/Calculator/Model/CalcEngine.swift > "$scratch/selected"
grep -qx CalcTests "$scratch/selected" || { echo 'FAIL: a calculator model change omitted CalcTests'; exit 1; }
[ ! -s "$scratch/unsure" ] || { echo "FAIL: a mapped Swift change was unsure: $(cat "$scratch/unsure")"; exit 1; }
echo 'PASS: a Swift file maps to its harness, and the selection is sure'
pick "$scratch/unsure" Tinycast/Features/Calculator/Model/CalcEngine.swift \
    Tinycast/Features/NoSuchFeature/Unmapped.swift Tests/Support/Unread.swift > "$scratch/selected"
for path in Tinycast/Features/NoSuchFeature/Unmapped.swift Tests/Support/Unread.swift; do
    grep -qx "unmapped: $path" "$scratch/unsure" || { echo "FAIL: $path did not make the selection unsure"; exit 1; }
done
echo 'PASS: a Tinycast/ or Tests/ path no harness names makes the selection unsure, beside mapped ones'
pick "$scratch/unsure" docs/standards.md notchcast/README.md > "$scratch/selected"
[ "$(cat "$scratch/selected")" = notchcast-hidden-features-test ] && [ ! -s "$scratch/unsure" ] \
    || { echo "FAIL: docs selected $(tr '\n' ' ' < "$scratch/selected")unsure: $(cat "$scratch/unsure")"; exit 1; }
echo 'PASS: docs select nothing beyond the always-run harness and are not unsure (lanes.py skips the build)'
for path in notchcast/changed-harnesses.sh Scripts/run-tests.sh notchcast/actions/tests/action.yml \
        .github/workflows/pr.yml; do
    pick "$scratch/unsure" "$path" > "$scratch/selected"
    grep -qx "runner: $path" "$scratch/unsure" || { echo "FAIL: a change to $path was not unsure"; exit 1; }
done
echo 'PASS: the selector and the runner never judge their own change'
for path in Tinycast/DesignSystem/BarButton.swift Tinycast/Platform/Memo.swift \
        Tinycast/Features/Notchcast/Core/Model/NotchcastPane.swift Tests/Kit/Island.kit; do
    pick "$scratch/unsure" "$path" > "$scratch/selected"
    grep -qx "shared: $path" "$scratch/unsure" || { echo "FAIL: shared $path was not unsure: $(cat "$scratch/unsure")"; exit 1; }
done
pick "$scratch/unsure" project.yml > "$scratch/selected"
grep -qx 'runner: project.yml' "$scratch/unsure" || { echo 'FAIL: project.yml was not unsure'; exit 1; }
echo 'PASS: shared code (DesignSystem, Platform, the add-on core, kits, project.yml) falls back to the whole suite'
addon=Tinycast/Features/Notchcast/ShowDesktop
pick "$scratch/unsure" "$addon/ShowDesktopAddon.swift" "$addon/Service/ShowDesktopModule.swift" \
    Tinycast/Features/Notchcast/NotchcastRegistry.swift Tests/nc-ShowDesktop-module-test.swift > "$scratch/selected"
for name in nc-ShowDesktop-module-test nc-Notchcast-registry-test; do
    grep -qx "$name" "$scratch/selected" || { echo "FAIL: an add-on change omitted $name"; exit 1; }
done
[ ! -s "$scratch/unsure" ] || { echo "FAIL: an add-on change was unsure: $(cat "$scratch/unsure")"; exit 1; }
if grep -qx -e CalcTests -e nc-QuitProtection-module-test "$scratch/selected"; then
    echo 'FAIL: an add-on change selected an unrelated harness'; exit 1
fi
echo 'PASS: an add-on change selects its own harness and the core registry harness, and is sure'
# A repo file a harness opens by a literal path, outside its sources and reads: a change to it must not be a sure
# selection, which would leave that harness out. A literal folder none of its inputs reach into is probed with a
# file name no harness can name.
(cd "$root" && python3 - > "$scratch/undeclared" <<'PY'
import fnmatch, re, sys
from pathlib import Path
sys.path.insert(0, 'notchcast')
from harness_inputs import harnesses
declared = {path: inputs.patterns + inputs.reads for path, inputs in harnesses()}
for path in sorted({*Path('Tests').glob('*-test.swift'), *Path('Tests').glob('*Tests.swift')}):
    for literal in sorted(set(re.findall(r'"([A-Za-z.][\w.+-]*/[^"\\\s]*)"', path.read_text(encoding='utf-8')))):
        if Path(literal).is_dir():
            literal = literal.rstrip('/') + '/no-harness-names-this'
            if any(pattern.startswith(literal.rsplit('/', 1)[0] + '/') for pattern in declared.get(path, [])):
                continue
        elif not Path(literal).is_file():
            continue
        if not any(fnmatch.fnmatchcase(literal, pattern) for pattern in declared.get(path, [])):
            print(path.stem, literal)
PY
)
grep -q . "$scratch/undeclared" || { echo 'FAIL: the scan for repo paths harnesses open found none'; exit 1; }
while read -r name path; do
    pick "$scratch/unsure" "$path" > "$scratch/selected"
    # harness-select.py also runs the whole suite when nothing beyond the always-run harness is selected.
    [ -s "$scratch/unsure" ] || [ "$(cat "$scratch/selected")" = notchcast-hidden-features-test ] || { echo "FAIL: $name opens $path, which is in none of its // notchcast-sources: or // notchcast-reads: lines, and a change to it selects only: $(tr '\n' ' ' < "$scratch/selected")"; exit 1; }
done < "$scratch/undeclared"
echo 'PASS: a repo file a harness opens is among its inputs, or a change to it runs the whole suite'
# verdict <changed paths...>: why the diff cannot land from Linux, one reason per line; nothing when it can.
verdict() { CHANGED="$*" bash "$root/notchcast/changed-harnesses.sh" --linux "$scratch/linux" base head > /dev/null; cat "$scratch/linux"; }
[ -z "$(verdict Tinycast/Features/Launcher/Model/FavoriteSlots.swift)" ] || { echo "FAIL: a linux-ok harness's input was kept off Linux: $(verdict Tinycast/Features/Launcher/Model/FavoriteSlots.swift)"; exit 1; }
[ -z "$(verdict docs/standards.md Tinycast/Features/NoSuchFeature/Unmapped.swift)" ] || { echo 'FAIL: docs or a path no harness names was kept off Linux'; exit 1; }
echo 'PASS: a diff reaching only linux-ok harnesses, or none, may land from Linux; the always-run harness does not count untouched'
[ "$(verdict Tinycast/Features/Launcher/Model/FavoriteSlots.swift Tinycast/Features/Calculator/Model/CalcEngine.swift)" = 'mac-only: CalcTests' ] \
    || { echo 'FAIL: one mac-only harness beside a linux-ok one did not route the diff to a Mac'; exit 1; }
verdict Tinycast/Features/Notchcast/Hidden/NotchcastHidden.swift | grep -qx 'mac-only: notchcast-hidden-features-test' \
    || { echo 'FAIL: the always-run harness did not count when the diff reached its inputs'; exit 1; }
echo 'PASS: one mac-only harness the diff reaches sends it to a Mac'
denied=$(sed -n 's/^LINUX_DENY_INPUTS="\([^ "]*\).*/\1/p' "$root/notchcast/config.env")
[ -n "$denied" ] && verdict "$denied" | grep -qx "denied: $denied" || { echo "FAIL: denied input '$denied' may land from Linux"; exit 1; }
verdict notchcast/config.env | grep -qx 'runner: notchcast/config.env' || { echo 'FAIL: a runner change may land from Linux'; exit 1; }
echo 'PASS: a LINUX_DENY_INPUTS path and a runner change never land from Linux'
for name in $(sed -n 's/^LINUX_OK_TESTS="\(.*\)"$/\1/p' "$root/notchcast/config.env"); do
    [ -f "$root/Tests/$name.swift" ] || { echo "FAIL: LINUX_OK_TESTS names $name, which is no harness"; exit 1; }
done
echo 'PASS: every LINUX_OK_TESTS name is a harness'
