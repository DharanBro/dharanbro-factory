#!/usr/bin/env bash
# new-worktree.sh <task> <repo> <branch>   worktree at tasks/<task>/<repo> from the repo's base branch. Idempotent.
. "$(dirname "$0")/lib.sh"
task="${1:?}"; repo="${2:?}"; branch="${3:?}"
src="$ROOT/repos/$repo"; dest="$ROOT/tasks/$task/$repo"
[ -d "$src/.git" ] || { echo "no base clone for $repo (run sync-repos.sh)" >&2; exit 1; }
[ -e "$dest" ] && { echo "$dest (exists)"; exit 0; }
base=$(repos_json | jq -r --arg r "$repo" '.repos[$r].branch // "main"')
git -C "$src" fetch -q origin
if git -C "$src" show-ref --verify -q "refs/heads/$branch"; then
  git -C "$src" worktree add -q "$dest" "$branch"
elif git -C "$src" show-ref --verify -q "refs/remotes/origin/$branch"; then
  git -C "$src" worktree add -q -b "$branch" "$dest" "origin/$branch"
else
  git -C "$src" worktree add -q --no-track -b "$branch" "$dest" "origin/$base"
fi
echo "$dest"
