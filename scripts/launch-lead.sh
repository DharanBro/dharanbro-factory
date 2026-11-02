#!/usr/bin/env bash
# launch-lead.sh <task>
# Herdr: ensure ONE workspace per task (label = task id) and a lead agent in it. Prints LAUNCHED|FOCUSED.
# Called from a Herdr pane (the master session): reuse that workspace, rename it to the task id, and
# after the caller's turn ends exit the caller and start the lead fresh in the same pane.
# New Herdr app (hc): ONE space per task (name = task id) with the lead in tab "lead"; the caller keeps running.
# No Herdr: prints INLINE (caller's session acts as lead).
. "$(dirname "$0")/lib.sh"
task="${1:?}"; td="$ROOT/tasks/$task"
R=$(runner "$task")
[ "$R" = headless ] && { echo INLINE; exit 0; }
C=$(conf "$task"); wsf="$td/work/workspace.json"
agent=$(stage_agent "$C" lead)
model=$(stage_model "$C" lead "$agent")
effort=$(stage_effort "$C" lead "$agent")
[ -n "$agent" ] && [ -n "$model" ] && [ -n "$effort" ] || { echo "lead needs agent, model and effort" >&2; exit 1; }
kind=$(jq -r --arg agent "$agent" '.agents[$agent].herdr.kind // empty' <<<"$C")
[ -n "$kind" ] || { echo "agents.$agent.herdr.kind is required" >&2; exit 1; }
lead=$(norm "$task-lead-$agent-$model-$effort")
args=()
while IFS= read -r a; do args+=("$(agent_arg "$a" "$td" "$ROOT" "$model" "$effort")"); done < <(jq -r --arg agent "$agent" --arg r "$R" '.agents[$agent].herdr.args[]?,
  (select($r == "hc") | .agents[$agent].herdr.hc_args[]?), .stages.lead.agents[$agent].herdr_args[]?' <<<"$C")
# Keep "in LEAD mode. TASK=<id> ": usage.sh finds the lead's session log by it.
prompt="Follow $ROOT/skills/factory/lead.md in LEAD mode. TASK=$task ROOT=$ROOT TASK_DIR=$td. Resume from state.json."

# Two leads must never advance one state file: refuse while the other Herdr app still runs this task's lead.
if [ "$R" = hc ]; then herdr agent get "$lead" >/dev/null 2>&1 && other="Herdr UI (herdr daemon)"
else case "$(hc_state "$lead")" in finished|gone) ;; *) other="the new Herdr app (hc)" ;; esac; fi
[ -z "${other:-}" ] || { echo "lead $lead is still running in $other; stop it there first" >&2; exit 1; }

if [ "$R" = hc ]; then
  case "$(hc_state "$lead")" in
    gone) ;;
    finished) hc rm "$lead" >/dev/null 2>&1 || true ;;
    *) herdr_app "do" agent.focus --terminal "$lead" >/dev/null 2>&1 || true; echo "FOCUSED space $task"; exit 0 ;;
  esac
  sp=$(jq -r '.hc_space // empty' "$wsf" 2>/dev/null || true)
  if [ -z "$sp" ] || ! herdr_app ls 2>/dev/null | jq -e --arg s "$sp" 'any(.spaces[]; .id == $s)' >/dev/null; then
    n=$(herdr_app "do" space.new --name "$task" --folder "$ROOT") || { echo "Herdr app window not reachable (space.new failed)" >&2; exit 1; }
    sp=$(jq -r .space <<<"$n"); shell=$(jq -r '.terminal // empty' <<<"$n")   # the space's default shell tab
    { cat "$wsf" 2>/dev/null || echo '{}'; } | jq --arg s "$sp" '.hc_space = $s' > "$wsf.tmp" && mv "$wsf.tmp" "$wsf"
  fi
  hc_spawn "$lead" "$sp" "$task" lead "$ROOT" "$prompt" "$kind" "${args[@]}" || exit 1
  [ -n "${shell:-}" ] && { hc kill "$shell" >/dev/null 2>&1 || true; hc rm "$shell" >/dev/null 2>&1 || true; }
  herdr_app "do" agent.focus --terminal "$lead" >/dev/null 2>&1 || true
  echo "LAUNCHED space $task"; exit 0
fi

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
