#!/usr/bin/env bash
# ci-run.sh <task> <repo>
# Run EVERY command in the repo's `ci_checks` (repos.yml) inside its worktree. Mechanical floor of the pre-PR
# gate: an agent cannot skip a check here. Writes artifacts/ci-runs-<repo>.md (pass/fail + output tail).
# Exit 0 = all passed, 1 = at least one failed, 2 = no ci_checks configured.
. "$(dirname "$0")/lib.sh"
task="${1:?}"; repo="${2:?}"
export FACTORY_ROOT="$ROOT"; wt="$ROOT/tasks/$task/$repo"; out="$ROOT/tasks/$task/artifacts/ci-runs-$repo.md"
[ -d "$wt" ] || { echo "no worktree $wt" >&2; exit 1; }
cmds=(); while IFS= read -r c; do [ -n "$c" ] && cmds+=("$c"); done < <(repos_json | jq -r --arg r "$repo" '.repos[$r].ci_checks[]?')
[ ${#cmds[@]} -gt 0 ] || { echo "no ci_checks for $repo" >&2; exit 2; }
fail=0; { echo "# ci-runs: $repo ($(date -u +%FT%TZ))"; echo; } > "$out"
for c in "${cmds[@]}"; do
  log=$(mktemp); ( cd "$wt" && bash -c "$c" ) >"$log" 2>&1 && rc=0 || rc=$?
  if [ $rc -eq 0 ]; then echo "- PASS: \`$c\`" >> "$out"; echo "PASS $c"
  else fail=1; echo "- FAIL($rc): \`$c\`" >> "$out"; { echo '```'; tail -n 15 "$log"; echo '```'; } >> "$out"; echo "FAIL($rc) $c"; fi
  rm -f "$log"
done
exit $fail
