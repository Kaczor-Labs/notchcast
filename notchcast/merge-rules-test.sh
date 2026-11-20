#!/bin/bash
# A fresh worker copy (git worktree add, as the gate's brief makes it) merges two add-on branches that append to
# every shared list with no conflict, using only the repo's files and the clone's core.hooksPath.
set -euo pipefail
root=$(git rev-parse --show-toplevel)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
git init --quiet -b main "$scratch/clone"
cd "$scratch/clone"
git config user.name Damian
git config user.email 336236323+kaczordodgers@users.noreply.github.com
git config core.hooksPath notchcast/githooks
mkdir -p notchcast/githooks notchcast/docs notchcast/licenses Tinycast/Features/Notchcast
cp "$root/.gitattributes" .gitattributes
cp "$root/notchcast/merge-words.py" notchcast/
cp "$root/notchcast/githooks/post-checkout" notchcast/githooks/
printf 'HOSTED_ONLY_TESTS="nc-a-test nc-b-test"\n' > notchcast/config.env
printf '| H1 | Commands, Timers |\n' > notchcast/docs/addons.md
printf -- '- Add-ons: Timers, Clock\n' > notchcast/README.public.md
printf 'Timers: Model/A.swift ← x/y@1/A.swift (MIT)\n' > notchcast/licenses/borrowed.md
printf '    TimersAddon.self,\n]\n' > Tinycast/Features/Notchcast/NotchcastRegistry.swift
git add -A
git commit --quiet -m base

add_addon() {
    git checkout --quiet -b "$1" main
    sed -i.orig "s/nc-b-test\"/nc-b-test nc-$1-test\"/" notchcast/config.env
    sed -i.orig "s/Timers |/Timers, $1 |/" notchcast/docs/addons.md
    sed -i.orig "s/Clock$/Clock, $1/" notchcast/README.public.md
    printf '%s: Model/B.swift ← x/y@1/B.swift (MIT)\n' "$1" >> notchcast/licenses/borrowed.md
    sed -i.orig '$d' Tinycast/Features/Notchcast/NotchcastRegistry.swift
    printf '    %sAddon.self,\n]\n' "$1" >> Tinycast/Features/Notchcast/NotchcastRegistry.swift
    rm notchcast/*.orig notchcast/docs/*.orig notchcast/*/*.orig Tinycast/Features/Notchcast/*.orig 2>/dev/null || true
    git commit --quiet -am "$1"
}
add_addon Spotify
add_addon Taildrop
git checkout --quiet main
git config --unset merge.notchcast-words.driver || true

git worktree add --quiet "$scratch/notchcast-g-000001" -b g-000001 Spotify
cd "$scratch/notchcast-g-000001"
git config --get merge.notchcast-words.driver >/dev/null \
    || { echo "FAIL: a fresh copy has no merge.notchcast-words.driver"; exit 1; }
git merge --quiet --no-edit Taildrop >/dev/null 2>&1 \
    || { echo "FAIL: conflict in $(git diff --name-only --diff-filter=U | tr '\n' ' ')"; exit 1; }
for name in Spotify Taildrop; do
    for file in notchcast/config.env notchcast/docs/addons.md notchcast/README.public.md \
        notchcast/licenses/borrowed.md Tinycast/Features/Notchcast/NotchcastRegistry.swift; do
        grep -q "$name" "$file" || { echo "FAIL: $file lost $name"; cat "$file"; exit 1; }
    done
done
echo "PASS: a fresh worker copy merges two add-on branches cleanly, both names in every shared list"
