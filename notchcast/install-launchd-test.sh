#!/bin/bash
# script-tests: macos (install-launchd.sh's BSD mv -h)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home with space"
mkdir -p "$HOME" "$WORK/origin/notchcast"
git init -q -b main "$WORK/origin"
git -C "$WORK/origin" config user.name Fixture
git -C "$WORK/origin" config user.email fixture@example.invalid
cp "$HERE/install-launchd.sh" "$HERE/config.env" "$HERE/install-app.sh" "$WORK/origin/notchcast/"
stub() { # file version
    printf '#!/bin/bash\nHERE="$(cd "$(dirname "$0")" && pwd)"\nsource "$HERE/config.env"\ntest -f "$HERE/install-app.sh"\necho "%s $APP_NAME $*"\n' \
        "$2" > "$WORK/origin/notchcast/$1"
}
stub update.sh update-v1
stub kick.sh kick-v1
printf '#!/bin/bash\n' > "$WORK/origin/notchcast/migrate.sh"
: > "$WORK/origin/notchcast/ci.py"
: > "$WORK/origin/notchcast/prune-branches.py"
printf 'OLD_APP="%s/no old app.app"\n' "$WORK" >> "$WORK/origin/notchcast/config.env"
git -C "$WORK/origin" add .
git -C "$WORK/origin" commit -qm v1
commit() { git -C "$WORK/origin" add .; git -C "$WORK/origin" commit -qm "$1"; }
git clone -q "$WORK/origin" "$WORK/checkout"
CHECKOUT="$WORK/checkout/notchcast/install-launchd.sh"
export WORK
launchctl() { echo "$*" >> "$WORK/launchctl.log"; }
export -f launchctl
PIN="$(sed -n 's/^RELEASE_SIGN_SHA1=//p' "$HERE/config.env")"
ENV="$HOME/.config/notchcast/private.env"
mkdir -p "$(dirname "$ENV")"
printf 'NOTCHCAST_OTHER=1' > "$ENV"
mkdir -p "$WORK/Notchcast.app"
NOTCHCAST_APP="$WORK/Notchcast.app" bash "$CHECKOUT" all
for label in update kick; do test -f "$HOME/Library/LaunchAgents/notchcast.$label.plist"; done
test ! -e "$HOME/Library/LaunchAgents/notchcast.app.plist" || { echo 'FAIL: all wrote a notchcast.app agent'; exit 1; }
! grep -q 'notchcast\.app' "$WORK/launchctl.log" || { echo 'FAIL: all ran launchctl on notchcast.app'; exit 1; }
STATUS=0
bash "$CHECKOUT" app 2>/dev/null || STATUS=$?
test "$STATUS" = 2 || { echo "FAIL: the app mode still exists (exit $STATUS)"; exit 1; }
echo 'PASS: all loads update and kick only; no app mode'

test "$(cat "$ENV")" = "NOTCHCAST_OTHER=1"$'\n'"SIGN_SHA1=$PIN" || { echo 'FAIL: private.env pin'; cat "$ENV"; exit 1; }
printf 'export SIGN_SHA1=%s\n' "$(printf '%040d' 0)" > "$ENV"
bash "$CHECKOUT" kick > /dev/null
test "$(cat "$ENV")" = "export SIGN_SHA1=$(printf '%040d' 0)" || { echo 'FAIL: installer replaced a pin'; exit 1; }
echo 'PASS: installer pins SIGN_SHA1 in private.env once and never replaces it'

CONFIG="$WORK/checkout/notchcast/config.env"
sed -i '' "s/^RELEASE_SIGN_SHA1=.*/RELEASE_SIGN_SHA1=$(printf '%040d' 1)/" "$CONFIG"
: > "$ENV"
bash "$CHECKOUT" kick > /dev/null 2>&1
test "$(cat "$ENV")" = "SIGN_SHA1=$PIN" || { echo 'FAIL: pinned an uncommitted RELEASE_SIGN_SHA1'; cat "$ENV"; exit 1; }
git -C "$WORK/checkout" checkout -q notchcast/config.env
printf 'export SIGN_SHA1=%s\n' "$(printf '%040d' 0)" > "$ENV"
echo "PASS: the pin comes from HEAD's config.env, never the working tree"

bash "$CHECKOUT" update --auto-install
WRAPPER="$HOME/Library/Application Support/notchcast/jobs/Notchcast update"
KICK="$HOME/Library/Application Support/notchcast/jobs/Notchcast sync check"
TOOLS="$HOME/Library/Application Support/notchcast/tools"
for label in update kick; do
    plist="$HOME/Library/LaunchAgents/notchcast.$label.plist"
    exe=$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$plist")
    test -x "$exe"
    test "$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:1' "$plist" 2>/dev/null || true)" = ''
    bash -n "$exe"
    ! grep -v '^tools=' "$exe" | grep -qE 'git|fetch|archive|origin' || { echo "FAIL: the $label job reaches for git"; cat "$exe"; exit 1; }
done
echo 'PASS: job wrappers never fetch or extract anything'

run() { # wrapper expected-line
    bash "$1" > "$WORK/log" 2>&1 || true
    grep -qx "$2" "$WORK/log" || { echo "FAIL: expected '$2'"; cat "$WORK/log"; exit 1; }
}
run "$WRAPPER" 'update-v1 Notchcast --install'
run "$KICK" 'kick-v1 Notchcast '
test "$(cut -d' ' -f1 "$TOOLS/.commit")" = "$(git -C "$WORK/checkout" rev-parse HEAD)"
echo 'PASS: jobs run the installed copy with their arguments'

for exe in "$WRAPPER" "$KICK"; do
    test "$(sed -n 2p "$exe")" = "tools=$(printf '%q' "$(readlink "$TOOLS")")" \
        || { echo 'FAIL: a wrapper runs the tools link, not the copy it points at'; cat "$exe"; exit 1; }
done
echo 'PASS: wrappers run the physical copy'

stub update.sh update-v2
stub kick.sh kick-v2
commit v2
git -C "$WORK/checkout" pull -q
run "$WRAPPER" 'update-v1 Notchcast --install'
run "$KICK" 'kick-v1 Notchcast '
echo 'PASS: a new origin main, even pulled into the checkout, never runs until the installer is rerun'

FIRST_COPY="$(readlink "$TOOLS")"
bash "$CHECKOUT" update --auto-install > /dev/null
run "$WRAPPER" 'update-v2 Notchcast --install'
run "$KICK" 'kick-v2 Notchcast '
SECOND_COPY="$(readlink "$TOOLS")"
test -d "$FIRST_COPY" || { echo 'FAIL: the previous copy is gone'; exit 1; }
printf 'echo dirty\n' >> "$WORK/checkout/notchcast/update.sh"
bash "$CHECKOUT" update --auto-install > /dev/null 2> "$WORK/err"
grep -q 'uncommitted changes' "$WORK/err" || { echo 'FAIL: no warning for uncommitted tooling'; exit 1; }
! grep -q dirty "$TOOLS/update.sh" || { echo 'FAIL: installed uncommitted tooling'; exit 1; }
test ! -e "${FIRST_COPY%/notchcast}" || { echo 'FAIL: an older copy was kept'; exit 1; }
test -d "$SECOND_COPY" || { echo 'FAIL: the previous copy is gone'; exit 1; }
git -C "$WORK/checkout" checkout -q notchcast/update.sh
echo 'PASS: rerunning the installer updates the copy from HEAD and keeps one previous copy'

mkdir -p "${TOOLS%/tools}/kick-tools.AbCdEf/notchcast"
ln -s "${TOOLS%/tools}/kick-tools.AbCdEf/notchcast" "${TOOLS%/tools}/kick-tools"
bash "$CHECKOUT" kick > /dev/null
test ! -e "${TOOLS%/tools}/kick-tools" && test ! -e "${TOOLS%/tools}/kick-tools.AbCdEf" \
    || { echo 'FAIL: the old kick copy stayed'; exit 1; }
echo 'PASS: the installer removes the old sync check copy'

COPY="$(readlink "$TOOLS")"
git -C "$WORK/origin" rm -q notchcast/ci.py
commit 'no ci.py'
git -C "$WORK/checkout" pull -q
PINNED="$(cat "$ENV")"
: > "$ENV"
if bash "$CHECKOUT" kick > /dev/null 2>&1; then echo 'FAIL: installed tooling that lacks ci.py'; exit 1; fi
test "$(readlink "$TOOLS")" = "$COPY" || { echo 'FAIL: an incomplete install replaced the copy'; exit 1; }
test ! -s "$ENV" || { echo 'FAIL: a failed tools copy wrote the pin'; cat "$ENV"; exit 1; }
printf '%s\n' "$PINNED" > "$ENV"
git -C "$WORK/origin" revert --no-edit HEAD > /dev/null
git -C "$WORK/checkout" pull -q
echo 'PASS: an incomplete HEAD keeps the installed copy and writes no pin'

sed -i '' 's/^RELEASE_SIGN_SHA1=.*/RELEASE_SIGN_SHA1=not-a-sha/' "$WORK/origin/notchcast/config.env"
commit 'bad pin'
git -C "$WORK/checkout" pull -q
: > "$ENV"
if bash "$CHECKOUT" kick > /dev/null 2>&1; then echo 'FAIL: pinned a malformed RELEASE_SIGN_SHA1'; exit 1; fi
test ! -s "$ENV" || { echo 'FAIL: wrote a malformed pin'; cat "$ENV"; exit 1; }
git -C "$WORK/origin" revert --no-edit HEAD > /dev/null
git -C "$WORK/checkout" pull -q
printf '%s\n' "$PINNED" > "$ENV"
echo 'PASS: a malformed committed RELEASE_SIGN_SHA1 is never pinned'

git -C "$WORK/checkout" worktree add -q --detach "$WORK/linked"
cp "$HERE/install-launchd.sh" "$WORK/linked/notchcast/"
/bin/bash "$WORK/linked/notchcast/install-launchd.sh" prune
plist="$HOME/Library/LaunchAgents/notchcast.prune.plist"
test "$(/usr/libexec/PlistBuddy -c 'Print :WorkingDirectory' "$plist")" = "$(cd "$WORK/checkout" && pwd -P)" \
    || { echo 'FAIL: prune job does not run in the main checkout'; exit 1; }
grep -qF 'Application\ Support/notchcast/tools/prune-branches.py --remote --local --log' "$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$plist")" \
    || { echo 'FAIL: prune job does not run the tools copy without roots'; exit 1; }
git -C "$WORK/checkout" worktree remove --force "$WORK/linked"
run "$KICK" 'kick-v2 Notchcast '
echo 'PASS: prune installs from a linked worktree into the main checkout; jobs outlive the worktree'

rm -rf "$(readlink "$TOOLS")" "$TOOLS"
printf '#!/bin/bash\necho checkout\n' > "$WORK/checkout/notchcast/update.sh"
if bash "$WRAPPER" > "$WORK/log" 2>&1; then echo 'FAIL: update ran with no installed tooling'; exit 1; fi
! grep -qx checkout "$WORK/log" || { echo 'FAIL: update ran the checkout'; exit 1; }
grep -q 'no installed tooling' "$WORK/log"
echo 'PASS: with no installed copy the jobs refuse and never run the checkout'
