#!/usr/bin/env bash
# worker-done.sh <task> <key> <done|blocked|failed> "<one-line summary>" ['{"extra":"json"}']
# A worker's LAST action. The lead reads only this tiny file, never the worker's chat.
. "$(dirname "$0")/lib.sh"
task="${1:?}"; key="${2:?}"; status="${3:?}"; summary="${4:-}"; extra="${5:-}"
[ -n "$extra" ] || extra='{}'
case "$status" in done|blocked|failed) ;; *) echo "bad status" >&2; exit 1 ;; esac
out="$ROOT/tasks/$task/work/$key.json"
jq -n --arg k "$key" --arg s "$status" --arg m "${summary:0:300}" --arg t "$(date -u +%FT%TZ)" --argjson x "$extra" \
  '{key:$k,status:$s,summary:$m,at:$t}+$x' > "$out.tmp" && mv "$out.tmp" "$out"
