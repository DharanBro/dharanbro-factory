#!/usr/bin/env bash
# launch-lead.sh <task>
# Herdr: ensure ONE workspace per task (label = task id) and a lead agent in it. Prints LAUNCHED|FOCUSED.
# No Herdr: prints INLINE (caller's session acts as lead).
. "$(dirname "$0")/lib.sh"
task="${1:?}"; td="$ROOT/tasks/$task"
[ "$(runner "$task")" = herdr ] || { echo INLINE; exit 0; }
C=$(conf "$task"); wsf="$td/work/workspace.json"; lead=$(norm "$task-lead")

ws=$(jq -r '.workspace_id // empty' "$wsf" 2>/dev/null || true)
if [ -n "$ws" ] && herdr workspace get "$ws" >/dev/null 2>&1; then
  herdr agent get "$lead" >/dev/null 2>&1 && { herdr workspace focus "$ws" >/dev/null; echo FOCUSED; exit 0; }
  t=$(herdr tab create --workspace "$ws" --cwd "$ROOT" --label lead --focus); pane=$(jq -r .result.root_pane.pane_id <<<"$t")
else
  w=$(herdr workspace create --cwd "$ROOT" --label "$task" --focus)
  ws=$(jq -r .result.workspace.workspace_id <<<"$w"); pane=$(jq -r .result.root_pane.pane_id <<<"$w")
  jq -n --arg w "$ws" '{workspace_id:$w}' > "$wsf"
fi

args=(--model "$(jq -r '.stages.lead.model' <<<"$C")")
e=$(jq -r '.stages.lead.effort // empty' <<<"$C"); [ -n "$e" ] && args+=(--effort "$e")
args+=(--settings "$ROOT/worker-settings.json" --add-dir "$td")
herdr_spawn "$lead" "$pane" "Follow $ROOT/.claude/skills/factory/SKILL.md in LEAD mode. TASK=$task ROOT=$ROOT TASK_DIR=$td. Resume from state.json; only read state.json + work/*.json summaries." "${args[@]}" || exit 1
echo LAUNCHED
