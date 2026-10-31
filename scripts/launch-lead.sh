#!/usr/bin/env bash
# launch-lead.sh <task>
# Herdr: ensure ONE workspace per task (label = task id) and a lead agent in it. Prints LAUNCHED|FOCUSED.
# Called from a Herdr pane (the master session): reuse that workspace, rename it to the task id, and
# after the caller's turn ends exit the caller and start the lead fresh in the same pane.
# No Herdr: prints INLINE (caller's session acts as lead).
. "$(dirname "$0")/lib.sh"
task="${1:?}"; td="$ROOT/tasks/$task"
[ "$(runner "$task")" = herdr ] || { echo INLINE; exit 0; }
C=$(conf "$task"); wsf="$td/work/workspace.json"
agent=$(stage_agent "$C" lead)
model=$(stage_model "$C" lead "$agent")
effort=$(stage_effort "$C" lead "$agent")
[ -n "$agent" ] && [ -n "$model" ] && [ -n "$effort" ] || { echo "lead needs agent, model and effort" >&2; exit 1; }
kind=$(jq -r --arg agent "$agent" '.agents[$agent].herdr.kind // empty' <<<"$C")
[ -n "$kind" ] || { echo "agents.$agent.herdr.kind is required" >&2; exit 1; }
lead=$(norm "$task-lead-$agent-$model-$effort")

ws=$(jq -r '.workspace_id // empty' "$wsf" 2>/dev/null || true)
if [ -n "$ws" ] && herdr workspace get "$ws" >/dev/null 2>&1; then
  herdr agent get "$lead" >/dev/null 2>&1 && { herdr workspace focus "$ws" >/dev/null; echo FOCUSED; exit 0; }
  t=$(herdr tab create --workspace "$ws" --cwd "$ROOT" --label lead --focus); pane=$(jq -r .result.root_pane.pane_id <<<"$t")
elif [ -n "${HERDR_PANE_ID:-}" ] && [ -n "${HERDR_WORKSPACE_ID:-}" ]; then
  ws=$HERDR_WORKSPACE_ID; pane=$HERDR_PANE_ID
  herdr workspace rename "$ws" "$task" >/dev/null
  jq -n --arg w "$ws" '{workspace_id:$w}' > "$wsf"
  handoff=1
else
  w=$(herdr workspace create --cwd "$ROOT" --label "$task" --focus)
  ws=$(jq -r .result.workspace.workspace_id <<<"$w"); pane=$(jq -r .result.root_pane.pane_id <<<"$w")
  jq -n --arg w "$ws" '{workspace_id:$w}' > "$wsf"
fi

args=()
while IFS= read -r a; do args+=("$(agent_arg "$a" "$td" "$ROOT" "$model" "$effort")"); done < <(jq -r --arg agent "$agent" '.agents[$agent].herdr.args[]?, .stages.lead.agents[$agent].herdr_args[]?' <<<"$C")
# Keep "in LEAD mode. TASK=<id> ": usage.sh finds the lead's session log by it.
prompt="Follow $ROOT/skills/factory/lead.md in LEAD mode. TASK=$task ROOT=$ROOT TASK_DIR=$td. Resume from state.json."
if [ -n "${handoff:-}" ]; then
  # Detached: wait for the caller agent to go idle, exit it (pane drops to its shell), start the lead there.
  ( herdr agent wait "$pane" --timeout 600000 >/dev/null 2>&1
    herdr pane send-text "$pane" "/exit" >/dev/null && herdr pane send-keys "$pane" enter >/dev/null
    sleep 3
    herdr_spawn "$kind" "$lead" "$pane" "$prompt" "${args[@]}" ) </dev/null >>"$td/work/lead-launch.log" 2>&1 &
  disown
else
  herdr_spawn "$kind" "$lead" "$pane" "$prompt" "${args[@]}" || exit 1
fi
echo LAUNCHED
