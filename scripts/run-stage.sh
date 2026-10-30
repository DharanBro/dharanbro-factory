#!/usr/bin/env bash
# run-stage.sh <task> <skill> <stage> [repo]
# Run one configured worker and block until it writes tasks/<task>/work/<key>.json.
# Env: EXTRA="free text appended to prompt" (e.g. "mode=fix report=artifacts/x.md"), TRY=<n> (key suffix -t<n>).
# Prints one line: "<key> <status> <summary>". Exit 0 = done, 2 = blocked/failed/timeout, 3 = needs human but no Herdr,
# 4 = interactive (grill) agent still alive in its tab at the deadline: not a failure, keep waiting for work/<key>.json.
. "$(dirname "$0")/lib.sh"
task="${1:?}"; skill="${2:?}"; stage="${3:?}"; repo="${4:-}"
key="$stage${repo:+-$repo}${TRY:+-t$TRY}"
td="$ROOT/tasks/$task"; wf="$td/work/$key.json"; mkdir -p "$td/work"
C=$(conf "$task"); R=$(runner "$task")
cfg() { jq -r "$1" <<<"$C"; }
agent=$(stage_agent "$C" "$stage")
model=$(stage_model "$C" "$stage" "$agent")
effort=$(stage_effort "$C" "$stage" "$agent")
[ -n "$agent" ] && [ -n "$model" ] && [ -n "$effort" ] || { echo "$key failed missing agent, model for '$agent', or effort in factory.yml"; exit 2; }
acfg() { jq -r --arg agent "$agent" "$1" <<<"$C"; }
[ "$(acfg '.agents[$agent] != null')" = true ] || { echo "$key failed unknown agent: $agent"; exit 2; }

interactive=0; [ "$stage" = grill ] && interactive=1
tmo=$(cfg '.caps.stage_timeout_min // 90'); [ $interactive = 1 ] && tmo=$(cfg '.caps.grill_timeout_min // 480')

# Working dir: factory root, or the repo checkout for repo stages.
cwd="$ROOT"
if [ -n "$repo" ]; then
  if [ "$stage" = research ]; then cwd="$ROOT/repos/$repo"; else cwd="$td/$repo"; fi
  [ -d "$cwd" ] || { echo "$key failed missing dir $cwd"; exit 2; }
fi
[ $interactive = 1 ] && [ "$R" != herdr ] && { echo "$key needs-human run grill inline (no Herdr)"; exit 3; }

skill_file="$ROOT/skills/$skill/SKILL.md"
[ -f "$skill_file" ] || { echo "$key failed missing playbook $skill_file"; exit 2; }
run=$(uuidgen); stamp="$td/work/$key.stamp"; : > "$stamp"   # RUN= marks this worker's session log for usage.sh
prompt="Follow $ROOT/AGENTS.md and $skill_file exactly. TASK=$task ROOT=$ROOT TASK_DIR=$td REPO=${repo:--} KEY=$key RUN=$run ${EXTRA:+EXTRA=\"$EXTRA\" }Your LAST action must be: bash $ROOT/scripts/worker-done.sh $task $key <done|blocked|failed> \"<one-line summary>\" . Be terse in chat; put detail in files."

# Backends may consume this standard Playwright MCP config via their own CLI or wrapper.
if [ "$stage" = ui_test ]; then
  mkdir -p "$ROOT/.browser-profile"
  chrome=$("$ROOT/scripts/chrome-path.sh") || { echo "$key failed Chrome for Testing unavailable"; exit 2; }
  export FACTORY_UI_MCP_CONFIG="$td/work/ui-mcp.json"
  jq -n --arg exe "$chrome" --arg prof "$ROOT/.browser-profile" \
    '{mcpServers:{playwright:{command:"npx",args:["@playwright/mcp@latest","--executable-path",$exe,"--user-data-dir",$prof,"--headless"]}}}' \
    > "$FACTORY_UI_MCP_CONFIG"
fi

rm -f "$wf"
tab=""; name=""
# Close this stage's leftover tabs from earlier attempts that finished, died or were
# killed (idle/unknown/done). Never touches working or blocked tabs, nor the current one.
close_stale_tabs() {
  herdr tab list --workspace "${tab%%:*}" 2>/dev/null |
    jq -r --arg key "$key" --arg current "$tab" \
      '.result.tabs[] | select(.label == $key and (.agent_status | IN("idle","unknown","done")) and .tab_id != $current) | .tab_id' 2>/dev/null |
    while IFS= read -r old_tab; do herdr tab close "$old_tab" >/dev/null 2>&1 || true; done
}
if [ "$R" = herdr ]; then
  kind=$(acfg '.agents[$agent].herdr.kind // empty')
  [ -n "$kind" ] || { echo "$key failed agents.$agent.herdr.kind is required"; exit 2; }
  args=()
  while IFS= read -r a; do args+=("$(agent_arg "$a" "$td" "$cwd" "$model" "$effort")"); done < <(jq -r --arg agent "$agent" --arg stage "$stage" '.agents[$agent].herdr.args[]?, .stages[$stage].agents[$agent].herdr_args[]?' <<<"$C")
  ws=$(jq -r '.workspace_id // empty' "$td/work/workspace.json" 2>/dev/null || true); ws="${ws:-${HERDR_WORKSPACE_ID:-}}"
  focus=--no-focus; [ $interactive = 1 ] && focus=--focus
  t=$(herdr tab create ${ws:+--workspace "$ws"} --cwd "$cwd" --label "$key" $focus)
  pane=$(jq -r .result.root_pane.pane_id <<<"$t"); tab=$(jq -r .result.tab.tab_id <<<"$t")
  [ "$(cfg '.keep_done_tabs // false')" = true ] || close_stale_tabs
  name=$(norm "$task-$key-$agent-$tab")
  herdr_spawn "$kind" "$name" "$pane" "$prompt" "${args[@]}" || { echo "$key failed agent start"; exit 2; }
  [ $interactive = 1 ] && herdr notification show "$task: grill ready" --body "Answer in tab '$key'" --sound request >/dev/null || true
  deadline=$(( $(date +%s) + tmo * 60 )); warned=0; alive=1
  while [ ! -s "$wf" ]; do
    if ! herdr agent get "$name" >/dev/null 2>&1; then alive=0; sleep 3; break; fi
    [ "$(date +%s)" -gt "$deadline" ] && break
    if [ $warned = 0 ] && herdr agent get "$name" 2>/dev/null | grep -q '"blocked"'; then
      herdr notification show "$task: $key blocked" --body "Worker waits on approval/question. Open tab '$key'." --sound request >/dev/null || true; warned=1
    fi
    sleep 5
  done
  # A human can take longer than any cap; while the grill's agent lives, it has not failed.
  if [ $interactive = 1 ] && [ $alive = 1 ] && [ ! -s "$wf" ]; then
    echo "$key running still open in tab '$key' after $tmo min; wait for $wf (pr-watch.sh --file)"; exit 4
  fi
else
  cmd=()
  while IFS= read -r a; do cmd+=("$(agent_arg "$a" "$td" "$cwd" "$model" "$effort")"); done < <(jq -r --arg agent "$agent" --arg stage "$stage" '.stages[$stage].agents[$agent].command[]?' <<<"$C")
  if [ ${#cmd[@]} -eq 0 ]; then
    while IFS= read -r a; do cmd+=("$(agent_arg "$a" "$td" "$cwd" "$model" "$effort")"); done < <(acfg '.agents[$agent].headless.command[]?')
  fi
  [ ${#cmd[@]} -gt 0 ] || { echo "$key failed agents.$agent.headless.command is required"; exit 2; }
  command -v "${cmd[0]}" >/dev/null 2>&1 || { echo "$key failed command not found: ${cmd[0]}"; exit 2; }
  delivery=$(acfg '.agents[$agent].headless.prompt_delivery // "stdin"')
  case "$delivery" in
    stdin) ( cd "$cwd" && printf '%s\n' "$prompt" | "${cmd[@]}" >"$td/work/$key.log" 2>&1 ) || true ;;
    argument) ( cd "$cwd" && "${cmd[@]}" "$prompt" >"$td/work/$key.log" 2>&1 ) || true ;;
    *) echo "$key failed unsupported prompt_delivery: $delivery"; exit 2 ;;
  esac
fi

bash "$ROOT/scripts/usage.sh" log "$task" "$key" "$agent" "$run" "$stamp" || true; rm -f "$stamp"
if [ -s "$wf" ]; then
  status=$(jq -r .status "$wf"); summary=$(jq -r .summary "$wf")
else
  status=failed; summary="no status file (timeout or worker died; see work/$key.log)"
  [ "$R" = herdr ] && summary="no status file (timeout or worker died; open tab '$key')"
fi
if [ "$R" = herdr ]; then
  if [ "$status" = done ] && [ "$(cfg '.keep_done_tabs // false')" != true ]; then
    close_stale_tabs
    herdr tab close "$tab" >/dev/null 2>&1 || true
  else herdr notification show "$task: $key $status" --body "$summary" --sound request >/dev/null 2>&1 || true; fi
fi
echo "$key $status $summary"
[ "$status" = done ] || exit 2
