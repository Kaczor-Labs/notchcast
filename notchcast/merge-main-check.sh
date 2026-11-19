#!/bin/bash
# Pre-push, per ref: refuses a merge of main into a PR branch whose old tip already merged onto main without a
# conflict, since the landing train merges main itself. Usage: merge-main-check.sh <local sha> <remote ref> <remote sha>
set -euo pipefail
local_sha=$1 remote_ref=$2 remote_sha=$3
tools=$(cd "$(dirname "$0")" && pwd)
[[ "$remote_ref" == refs/heads/* && "$remote_ref" != refs/heads/main && ! "$remote_sha" =~ ^0+$ && ! "$local_sha" =~ ^0+$ ]] || exit 0
main=$(git rev-parse --verify -q refs/remotes/origin/main) || exit 0
git cat-file -e "$remote_sha^{commit}" 2>/dev/null || exit 0
merge=
for commit in $(git rev-list --merges "$remote_sha..$local_sha"); do
    for parent in $(git rev-list --no-walk --parents "$commit" | cut -d' ' -f3-); do
        if git merge-base --is-ancestor "$parent" "$main" && ! git merge-base --is-ancestor "$parent" "$remote_sha"; then merge=$commit; fi
    done
    [ -z "$merge" ] || break
done
[ -n "$merge" ] || exit 0
# The old tip onto main as the train merges it: from its fork point, by word where marked, main's generated files kept.
fork=$(bash "$tools/fork-point.sh" "$main" "$remote_sha") || exit 0
status=0
conflicts=$(git -c "merge.notchcast-words.driver=python3 '$tools/merge-words.py' %O %A %B" \
    merge-tree --write-tree --name-only --no-messages --merge-base "$fork" "$main" "$remote_sha" | tail -n +2) || status=$?
[ "$status" -le 1 ] || exit 0
generated=$(PYTHONPATH="$tools/.." python3 -c 'from notchcast.ci import GENERATED; print("\n".join(GENERATED))') || exit 0
[ -z "$(grep -vxF "$generated" <<< "$conflicts" | grep . || true)" ] || exit 0
branch=${remote_ref#refs/heads/}
echo "REFUSED: this push merges main into $branch (${merge:0:8}), and $branch at ${remote_sha:0:8} merges onto main without a conflict; the landing train merges main itself, so nobody merges main into a PR branch. Drop the merge: git rebase --onto ${merge:0:8}^1 ${merge:0:8}, then push again. A merge that resolves a real conflict with main passes." >&2
exit 1
