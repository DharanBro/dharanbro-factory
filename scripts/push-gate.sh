#!/usr/bin/env bash
# push-gate.sh <task> <repo>   Run before EVERY push of a task branch (workers and lead). Exit 0 = safe to push.
# Checks, in the repo's worktree: tree clean, base branch merged in, Sonar verdict OK (when the repo has sonar.project_key),
# local CodeRabbit CLI review of the branch diff has 0 findings. Anything it could not verify is a failure (UNVERIFIED), never a pass.
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
  bash "$ROOT/scripts/sonar-scan.sh" "$task" "$repo" > /dev/null 2>"$out.sonar"; rc=$?
  case $rc in 0) ;; 1) fail "Sonar verdict ERROR: fix every issue listed in artifacts/sonar-$repo.md (changed lines and new issues in changed files).";;
    *) fail "UNVERIFIED: Sonar scan did not run (exit $rc): $(tail -n 2 "$out.sonar" | tr '\n' ' ')";; esac
  rm -f "$out.sonar"
else body="Sonar: skipped, no sonar.project_key for $repo."$'\n'; fi

if ! command -v coderabbit >/dev/null; then fail "UNVERIFIED: coderabbit CLI not installed."
elif ! coderabbit auth status --agent 2>/dev/null | grep -q '"authenticated":true'; then fail "UNVERIFIED: CodeRabbit CLI not authenticated: run \`coderabbit auth login\`."
else
  cr=$(coderabbit review --agent --type committed --base "origin/$base" --cwd "$wt" 2>&1) || true
  n=$(jq -R 'fromjson? | select(.type=="complete") | .findings' <<<"$cr" | tail -n 1)
  if [ -z "$n" ]; then fail "UNVERIFIED: CodeRabbit CLI returned no result (rate limit or error): $(tail -c 300 <<<"$cr" | tr '\n' ' ')"
  elif [ "$n" != 0 ]; then
    # findings already answered in artifacts/push-gate-answers-<repo>.md (file + match key + reason) do not block; they are listed in the report
    res=$(python3 -I "$ROOT/scripts/cr-answers.py" "$ROOT/tasks/$task/artifacts/push-gate-answers-$repo.md" <<<"$cr")
    open=$(grep '^O ' <<<"$res" | cut -c3-); ans=$(grep '^A ' <<<"$res" | cut -c3-)
    [ -n "$open$ans" ] || open="$n finding(s) reported but none could be read from the CLI output"
    [ -z "$ans" ] || body="$body"$'\n'"## CodeRabbit CLI findings answered (no change needed)"$'\n'"$(sed 's/^/- /' <<<"$ans")"$'\n'
    if [ -n "$open" ]; then
      fail "CodeRabbit CLI reported $(wc -l <<<"$open" | tr -d ' ') open finding(s): fix each, commit, run the gate again. Only if existing code already handles one, add an answer line to artifacts/push-gate-answers-$repo.md."
      body="$body"$'\n'"## CodeRabbit CLI findings"$'\n'"$(sed 's/^/- /' <<<"$open")"$'\n'
    fi
  fi
fi

{ echo "# push gate: $repo @ ${head:0:10} ($(date -u +%FT%TZ))"; echo
  if [ -z "$bad" ]; then echo "**PASS**: safe to push."; else echo "**FAIL**:"; printf '%s' "$bad"; fi
  printf '%s\n' "$body"; } > "$out"
if [ -z "$bad" ]; then echo "$head" > "$ok"; echo "PASS $out"; else printf 'FAIL %s\n%s' "$out" "$bad" >&2; exit 1; fi
