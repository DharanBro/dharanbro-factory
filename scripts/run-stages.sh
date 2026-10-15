#!/usr/bin/env bash
# run-stages.sh <task> <skill> <stage> <repo> [repo...]   one worker per repo, in parallel (capped by max_parallel_workers)
. "$(dirname "$0")/lib.sh"
task="${1:?}"; skill="${2:?}"; stage="${3:?}"; shift 3
[ $# -gt 0 ] || { echo "no repos" >&2; exit 1; }
max=$(conf "$task" | jq -r '.max_parallel_workers // 4')
printf '%s\n' "$@" | xargs -P "$max" -I{} "$ROOT/scripts/run-stage.sh" "$task" "$skill" "$stage" {}
