#!/usr/bin/env bash
# ci-run.sh <task> <repo>
# Run EVERY command in the repo's `ci_checks` (repos.yml) inside its worktree. Mechanical floor of the pre-PR
# gate: an agent cannot skip a check here. Writes artifacts/ci-runs-<repo>.md (pass/fail + output tail).
# A failing command is re-run in a throwaway detached worktree at origin/<base> (after the repo's `install`, if
# set). Same exit code there -> PRE-EXISTING(rc): the branch did not cause it, so it is reported but left out of
# the exit code, and listed in artifacts/ci-preexisting-<repo>.json as [{cmd, rc}].
# Exit 0 = all passed (or only pre-existing failures), 1 = at least one failure the branch owns, 2 = no ci_checks.
. "$(dirname "$0")/lib.sh"
task="${1:?}"; repo="${2:?}"
export FACTORY_ROOT="$ROOT"; wt="$ROOT/tasks/$task/$repo"; art="$ROOT/tasks/$task/artifacts"
out="$art/ci-runs-$repo.md"; pre_json="$art/ci-preexisting-$repo.json"
[ -d "$wt" ] || { echo "no worktree $wt" >&2; exit 1; }
cmds=(); while IFS= read -r c; do [ -n "$c" ] && cmds+=("$c"); done < <(repos_json | jq -r --arg r "$repo" '.repos[$r].ci_checks[]?')
[ ${#cmds[@]} -gt 0 ] || { echo "no ci_checks for $repo" >&2; exit 2; }
base=$(repos_json | jq -r --arg r "$repo" '.repos[$r].branch // "main"')
install=$(repos_json | jq -r --arg r "$repo" '.repos[$r].install // empty')

btmp=""; bwt=""; bstate=""   # base worktree, created on the first failure only
# shellcheck disable=SC2329  # invoked by the trap
cleanup() { [ -n "$bwt" ] && git -C "$wt" worktree remove --force "$bwt" >/dev/null 2>&1; [ -n "$btmp" ] && rm -rf "$btmp"; return 0; }
trap cleanup EXIT
# base_rc <cmd> <log>: sets brc to the exit code of <cmd> at origin/<base>, or "none" if that worktree cannot
# be set up. Sets a global instead of printing: a $(...) subshell would lose the worktree state.
base_rc() {
  if [ -z "$bstate" ]; then
    btmp=$(mktemp -d); bwt="$btmp/base"; bstate=ok
    { git -C "$wt" fetch -q origin "$base" && git -C "$wt" worktree add -q --detach "$bwt" "origin/$base"; } >/dev/null 2>&1 || { bwt=""; bstate=none; }
    [ "$bstate" = ok ] && [ -n "$install" ] && { ( cd "$bwt" && bash -c "$install" ) >/dev/null 2>&1 || true; }
  fi
  brc=none; [ "$bstate" = ok ] || return 0
  ( cd "$bwt" && bash -c "$1" ) >"$2" 2>&1 && brc=0 || brc=$?
}

fail=0; pre=(); { echo "# ci-runs: $repo ($(date -u +%FT%TZ))"; echo; } > "$out"
for c in "${cmds[@]}"; do
  log=$(mktemp); ( cd "$wt" && bash -c "$c" ) >"$log" 2>&1 && rc=0 || rc=$?
  if [ $rc -eq 0 ]; then echo "- PASS: \`$c\`" >> "$out"; echo "PASS $c"; rm -f "$log"; continue; fi
  base_rc "$c" "$log.base"
  if [ "$brc" = "$rc" ]; then
    pre+=("$(jq -cn --arg c "$c" --argjson rc "$rc" '{cmd:$c, rc:$rc}')")
    echo "- PRE-EXISTING($rc): \`$c\` (fails the same way on origin/$base; not caused by this branch)" >> "$out"; echo "PRE-EXISTING($rc) $c"
  else
    fail=1; echo "- FAIL($rc): \`$c\` (origin/$base: $( [ "$brc" = none ] && echo "not checked, base worktree unavailable" || echo "rc $brc"))" >> "$out"; echo "FAIL($rc) $c"
  fi
  { echo '```'; tail -n 15 "$log"; echo '```'; } >> "$out"
  rm -f "$log" "$log.base"
done
if [ ${#pre[@]} -gt 0 ]; then printf '%s\n' "${pre[@]}" | jq -s . > "$pre_json"; else echo '[]' > "$pre_json"; fi
exit $fail
