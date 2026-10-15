#!/usr/bin/env bash
# version-bump.sh [base-ref]   run inside a repo worktree. Mirrors the "Check version bumped" CI rule:
# all PR commits are `fix` (ignoring ": ci:" follow-ups) -> patch bump, anything else -> minor bump.
base="${1:-origin/master}"
old=$(git show "$base:package.json" | jq -r .version); new=$(jq -r .version package.json)
IFS=. read -r a b c <<<"${old%%-*}"
subjects=$(git log "$base..HEAD" --format=%s | grep -v ': ci:' || true)
if [ -n "$subjects" ] && ! grep -qvE '^fix(\(|:)' <<<"$subjects"; then want="$a.$b.$((c+1))"; kind="bug fix -> patch"
else want="$a.$((b+1)).0"; kind="not a bug fix -> minor"; fi
[ "$new" = "$want" ] || { echo "CI rule: package.json version must be $want ($kind); is $new (base $old)"; exit 1; }
echo "version ok: $old -> $new"
