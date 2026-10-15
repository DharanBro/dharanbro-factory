#!/usr/bin/env bash
# state.sh <task> get | next | set <stage> <status> | reset <stage> | update '<jq expr>'
# Single writer = the lead. Workers never touch state.json (they write work/<key>.json).
. "$(dirname "$0")/lib.sh"
id="${1:?task}"; cmd="${2:?cmd}"; f="$ROOT/tasks/$id/state.json"
[ -f "$f" ] || { echo "no state for $id (run task-init.sh)" >&2; exit 1; }
w() { jq "$@" "$f" > "$f.tmp" && mv "$f.tmp" "$f"; }
case "$cmd" in
  get)    jq -c . "$f" ;;
  next)   jq -r '[.stages|to_entries[]|select(.value!="done")][0].key // "complete"' "$f" ;;
  set)    w --arg s "${3:?stage}" --arg v "${4:?status}" '.stages[$s]=$v' ;;
  reset)  w --arg st "${3:?stage}" '(.stages|keys_unsorted) as $k | ($k|index($st)) as $i
            | .stages |= with_entries(. as $e | if ($k|index($e.key)) >= $i then .value="pending" else . end)' ;;
  update) w "${3:?jq expr}" ;;
  *) echo "bad cmd" >&2; exit 1 ;;
esac
