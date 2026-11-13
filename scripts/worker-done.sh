#!/usr/bin/env bash
# worker-done.sh <task> <key> <done|blocked|failed> "<one-line summary>" ['{"extra":"json"}']
# A worker's LAST action. The lead reads only this tiny file, never the worker's chat.
. "$(dirname "$0")/lib.sh"
task="${1:?}"; key="${2:?}"; status="${3:?}"; summary="${4:-}"; extra="${5:-}"
[ -n "$extra" ] || extra='{}'
case "$status" in done|blocked|failed) ;; *) echo "bad status" >&2; exit 1 ;; esac
out="$ROOT/tasks/$task/work/$key.json"
# A repo whose branch was pushed (upstream head) must have a passing push-gate.sh record for exactly that sha, else `done` becomes `failed`.
if [ "$status" = done ]; then
  for g in "$ROOT/tasks/$task"/*/.git; do
    [ -e "$g" ] || continue; d=$(dirname "$g"); r=$(basename "$d")
    u=$(git -C "$d" rev-parse -q --verify '@{u}' 2>/dev/null) || continue
    [ "$(cat "$ROOT/tasks/$task/work/push-gate-$r.ok" 2>/dev/null)" = "$u" ] && continue
    status=failed; summary="PUSH GATE: $r pushed ${u:0:10} without a passing push-gate.sh (see artifacts/push-gate-$r.md); fix the findings, run the gate, push again. Worker said: $summary"
  done
fi
jq -n --arg k "$key" --arg s "$status" --arg m "${summary:0:300}" --arg t "$(date -u +%FT%TZ)" --argjson x "$extra" \
  '{key:$k,status:$s,summary:$m,at:$t}+$x' > "$out.tmp" && mv "$out.tmp" "$out"
