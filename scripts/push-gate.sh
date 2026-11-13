#!/usr/bin/env bash
# push-gate.sh <task> <repo>   Run before EVERY push of a task branch (workers and lead). Exit 0 = safe to push.
# Checks, in the repo's worktree: tree clean, base branch merged in, Sonar verdict OK (when the repo has sonar.project_key),
# CodeRabbit review record (artifacts/cr-review-<repo>.md, written by the plugin review stage) is clean for HEAD, only for repos with
# `coderabbit: true`. Anything it could not verify is a failure (UNVERIFIED), never a pass.
# Writes artifacts/push-gate-<repo>.md; on pass writes work/push-gate-<repo>.ok holding the head sha. worker-done.sh refuses
# `done` when a repo's pushed head (@{u}) has no matching .ok, so a push that skipped the gate cannot be reported clean.
. "$(dirname "$0")/lib.sh"
task="${1:?}"; repo="${2:?}"
wt="$ROOT/tasks/$task/$repo"; out="$ROOT/tasks/$task/artifacts/push-gate-$repo.md"; ok="$ROOT/tasks/$task/work/push-gate-$repo.ok"
[ -d "$wt" ] || { echo "no worktree $wt" >&2; exit 1; }
mkdir -p "$(dirname "$out")" "$(dirname "$ok")"; rm -f "$ok"
base=$(repos_json | jq -r --arg r "$repo" '.repos[$r].branch // "main"')
key=$(repos_json | jq -r --arg r "$repo" '.repos[$r].sonar.project_key // empty')
head=$(git -C "$wt" rev-parse HEAD); bad=""; body=""
fail() { bad="$bad- $1"$'\n'; }

[ -z "$(git -C "$wt" status --porcelain)" ] || fail "UNCOMMITTED changes: commit or discard them; the gate verifies committed HEAD only."
git -C "$wt" fetch -q origin "$base" 2>/dev/null || fail "UNVERIFIED: git fetch origin $base failed."
git -C "$wt" merge-base --is-ancestor "origin/$base" HEAD || fail "origin/$base is not merged into this branch: merge it (merge, not rebase), re-run gates, then run the gate again."

if [ -n "$key" ]; then
  rc=0; bash "$SCRIPTS/sonar-scan.sh" "$task" "$repo" > /dev/null 2>"$out.sonar" || rc=$?
  case $rc in 0) ;; 1) fail "Sonar verdict ERROR: fix every issue listed in artifacts/sonar-$repo.md (changed lines and new issues in changed files).";;
    *) fail "UNVERIFIED: Sonar scan did not run (exit $rc): $(tail -n 2 "$out.sonar" | tr '\n' ' ')";; esac
  rm -f "$out.sonar"
else body="Sonar: skipped, no sonar.project_key for $repo."$'\n'; fi

# CodeRabbit: the review itself runs in the worker via the CodeRabbit plugin (skills/factory-coderabbit-review) and leaves
# artifacts/cr-review-<repo>.md; the gate only checks that record. Repos without `coderabbit: true` skip it.
rec="$ROOT/tasks/$task/artifacts/cr-review-$repo.md"; ans="$ROOT/tasks/$task/artifacts/push-gate-answers-$repo.md"
cr=$(bash "$SCRIPTS/cr-enabled.sh" "$repo") || { cr=error; fail "UNVERIFIED: cr-enabled.sh failed, cannot tell whether CodeRabbit is required for $repo."; }
if [ "$cr" = error ]; then :
elif [ "$cr" != true ]; then body="$body"$'\n'"CodeRabbit: skipped (off for $repo)."$'\n'
elif [ ! -f "$rec" ]; then fail "CodeRabbit review missing: run the review in skills/factory-coderabbit-review/SKILL.md, it writes artifacts/cr-review-$repo.md."
elif ! grep -qx "head: $head" "$rec" || ! grep -qx "result: clean" "$rec"; then
  fail "CodeRabbit review record is not clean for HEAD ${head:0:10} (stale or unresolved): rerun the review after your last commit or merge."
else
  # every finding line ends "fixed in <sha>" or "answered <file:line>"; an answered one also needs a `- <file> |` line in the answers file
  while IFS= read -r l; do
    case "$l" in
      *"| fixed in "[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]*) ;;
      *"| answered "*:[0-9]*) f=${l#- }; f=${f%% |*}
        grep -qF -- "- $f |" "$ans" 2>/dev/null || fail "CodeRabbit finding answered without an entry in artifacts/push-gate-answers-$repo.md: $l" ;;
      *) fail "CodeRabbit finding unresolved in cr-review-$repo.md: $l" ;;
    esac
  done < <(grep '^- ' "$rec")
  body="$body"$'\n'"CodeRabbit: clean record for ${head:0:10} ($(grep -c '^- ' "$rec") finding(s) resolved)."$'\n'
fi

{ echo "# push gate: $repo @ ${head:0:10} ($(date -u +%FT%TZ))"; echo
  if [ -z "$bad" ]; then echo "**PASS**: safe to push."; else echo "**FAIL**:"; printf '%s' "$bad"; fi
  printf '%s\n' "$body"; } > "$out"
if [ -z "$bad" ]; then echo "$head" > "$ok"; echo "PASS $out"; else printf 'FAIL %s\n%s' "$out" "$bad" >&2; exit 1; fi
