#!/bin/bash
set -euo pipefail

common=$(git rev-parse --path-format=absolute --git-common-dir)
hooks="$common/notchcast-hooks"
if ! git cat-file -e refs/remotes/origin/main:notchcast/install-hooks.sh; then
    echo 'install-hooks: fetch origin main before installing; origin/main must contain install-hooks.sh' >&2
    exit 1
fi

mkdir -p "$hooks"
stage=$(mktemp -d "$hooks/.install.XXXXXX")
trap 'rm -rf "$stage"' EXIT
cat > "$stage/dispatch" <<'SHIM'
#!/bin/bash
set -euo pipefail
hook=${0##*/}
ref=refs/remotes/origin/main
refuse() { echo "$hook: REFUSED: $*" >&2; exit 1; }

if [ "$hook" = pre-push ]; then
    git fetch --quiet --no-tags origin "+refs/heads/main:$ref" </dev/null \
        || refuse 'could not refresh origin/main'
fi
main=$(git rev-parse --verify "$ref^{commit}") || refuse 'no origin/main; run git fetch origin main'
git cat-file -e "$main:notchcast/install-hooks.sh" || refuse 'origin/main does not support installed hooks'

# Keep Git's working directory and index, and get executable files from the pinned ref.
tools=$(mktemp -d)
trap 'rm -rf "$tools"' EXIT
trap 'exit 1' HUP INT TERM
git archive -o "$tools/tools.tar" "$main" notchcast || refuse 'could not archive origin/main tools'
tar -xf "$tools/tools.tar" -C "$tools" || refuse 'could not extract origin/main tools'
script="$tools/notchcast/githooks/$hook"
[ -x "$script" ] || refuse "origin/main has no executable $hook"
"$script" "$@"
SHIM
chmod +x "$stage/dispatch"
mv -f "$stage/dispatch" "$hooks/dispatch"
for hook in commit-msg post-checkout pre-commit pre-push; do
    ln -s dispatch "$stage/$hook"
    mv -f "$stage/$hook" "$hooks/$hook"
done
git config --local core.hooksPath "$hooks"
echo "Installed Notchcast hooks in $hooks"
