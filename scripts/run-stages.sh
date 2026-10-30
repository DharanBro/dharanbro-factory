#!/usr/bin/env bash
# run-stages.sh <task> <skill> <stage> <repo...> | --wave <n> | --all
# One worker per repo, in parallel (capped by max_parallel_workers). --wave/--all resolve repos from plan-meta.sh.
# A repo list passed as one quoted string (zsh never splits "$repos") is split on whitespace.
# Every repo dir is checked before any worker starts: one missing -> "<stage> failed missing dir ..." and exit 2.
. "$(dirname "$0")/lib.sh"
task="${1:?}"; skill="${2:?}"; stage="${3:?}"; shift 3
# shellcheck disable=SC2048,SC2086
set -- $*   # repo names never contain spaces (repo-set.sh)
case "${1:-}" in
  --wave) repos=$(bash "$ROOT/scripts/plan-meta.sh" "$task" | jq -r --argjson w "${2:?wave number}" '.waves[] | select(.wave == $w) | .repos[]') ;;
  --all)  repos=$(bash "$ROOT/scripts/plan-meta.sh" "$task" | jq -r '.repos[]') ;;
  *)      repos="$*" ;;
esac
# shellcheck disable=SC2086
set -- $repos
[ $# -gt 0 ] || { echo "no repos" >&2; exit 1; }
missing=""
for r in "$@"; do
  if [ "$stage" = research ]; then d="$ROOT/repos/$r"; else d="$ROOT/tasks/$task/$r"; fi
  [ -d "$d" ] || missing="$missing $d"
done
[ -z "$missing" ] || { echo "$stage failed missing dir(s):$missing (no worker started)"; exit 2; }
max=$(conf "$task" | jq -r '.max_parallel_workers // 4')
printf '%s\n' "$@" | xargs -P "$max" -I{} "$ROOT/scripts/run-stage.sh" "$task" "$skill" "$stage" {}
