#!/usr/bin/env bash
# run-stage.sh <task> <skill> <stage> [repo]
# Run ONE worker (fresh claude session) and block until it writes tasks/<task>/work/<key>.json.
# Env: EXTRA="free text appended to prompt" (e.g. "mode=fix report=artifacts/x.md"), TRY=<n> (key suffix -t<n>).
# Prints one line: "<key> <status> <summary>". Exit 0 = done, 2 = blocked/failed/timeout, 3 = needs human but no Herdr.
. "$(dirname "$0")/lib.sh"
task="${1:?}"; skill="${2:?}"; stage="${3:?}"; repo="${4:-}"
key="$stage${repo:+-$repo}${TRY:+-t$TRY}"
td="$ROOT/tasks/$task"; wf="$td/work/$key.json"; mkdir -p "$td/work"
C=$(conf "$task"); R=$(runner "$task")
cfg() { jq -r "$1" <<<"$C"; }

model=$(cfg ".stages.${stage}.model // empty"); effort=$(cfg ".stages.${stage}.effort // empty")
[ -n "$model" ] || { echo "$key failed no model configured for stage '$stage' in factory.yml"; exit 2; }
interactive=0; [ "$stage" = grill ] && interactive=1
tmo=$(cfg '.caps.stage_timeout_min // 90'); [ $interactive = 1 ] && tmo=$(cfg '.caps.grill_timeout_min // 480')

# working dir: factory root (skills + CLAUDE.md load natively), or the repo checkout for repo stages
cwd="$ROOT"
if [ -n "$repo" ]; then
  if [ "$stage" = research ]; then cwd="$ROOT/repos/$repo"; else cwd="$td/$repo"; fi
  [ -d "$cwd" ] || { echo "$key failed missing dir $cwd"; exit 2; }
fi
[ $interactive = 1 ] && [ "$R" != herdr ] && { echo "$key needs-human run grill inline (no Herdr)"; exit 3; }

args=(--model "$model")
[ -n "$effort" ] && args+=(--effort "$effort")
args+=(--settings "$ROOT/worker-settings.json" --add-dir "$ROOT" --add-dir "$td")
while IFS= read -r a; do [ -n "$a" ] && args+=("$a"); done < <(cfg '.worker_args[]?')

if [ "$stage" = ui_test ]; then   # factory-owned browser: Chrome for Testing + factory profile, headless
  mkdir -p "$ROOT/.browser-profile"
  jq -n --arg exe "$("$ROOT/scripts/chrome-path.sh")" --arg prof "$ROOT/.browser-profile" \
    '{mcpServers:{playwright:{command:"npx",args:["@playwright/mcp@latest","--executable-path",$exe,"--user-data-dir",$prof,"--headless"]}}}' \
    > "$td/work/ui-mcp.json"
  args+=(--mcp-config "$td/work/ui-mcp.json" --strict-mcp-config)
fi

prompt="Follow $ROOT/.claude/skills/$skill/SKILL.md exactly. TASK=$task ROOT=$ROOT TASK_DIR=$td REPO=${repo:--} KEY=$key ${EXTRA:+EXTRA=\"$EXTRA\" }Your LAST action must be: bash $ROOT/scripts/worker-done.sh $task $key <done|blocked|failed> \"<one-line summary>\" . Be terse in chat; put detail in files."

rm -f "$wf"
export AUTO_TRUST=$(cfg '.auto_trust_worktrees // true')
tab=""; name=""
if [ "$R" = herdr ]; then
  ws=$(jq -r '.workspace_id // empty' "$td/work/workspace.json" 2>/dev/null || true); ws="${ws:-${HERDR_WORKSPACE_ID:-}}"
  focus=--no-focus; [ $interactive = 1 ] && focus=--focus
  t=$(herdr tab create ${ws:+--workspace "$ws"} --cwd "$cwd" --label "$key" $focus)
  pane=$(jq -r .result.root_pane.pane_id <<<"$t"); tab=$(jq -r .result.tab.tab_id <<<"$t")
  name=$(norm "$task-$key")
  herdr_spawn "$name" "$pane" "$prompt" "${args[@]}" || { echo "$key failed agent start"; exit 2; }
  [ $interactive = 1 ] && herdr notification show "$task: grill ready" --body "Answer in tab '$key'" --sound request >/dev/null || true
  deadline=$(( $(date +%s) + tmo * 60 )); warned=0
  while [ ! -s "$wf" ]; do
    [ "$(date +%s)" -gt "$deadline" ] && break
    if ! herdr agent get "$name" >/dev/null 2>&1; then sleep 3; break; fi
    if [ $warned = 0 ] && herdr agent get "$name" 2>/dev/null | grep -q '"blocked"'; then
      herdr notification show "$task: $key blocked" --body "Worker waits on approval/question. Open tab '$key'." --sound request >/dev/null || true; warned=1
    fi
    sleep 5
  done
else
  ( cd "$cwd" && claude -p "$prompt" "${args[@]}" >"$td/work/$key.log" 2>&1 ) || true
fi

if [ -s "$wf" ]; then
  status=$(jq -r .status "$wf"); summary=$(jq -r .summary "$wf")
else
  status=failed; summary="no status file (timeout or worker died; see work/$key.log or open tab)"
fi
if [ "$R" = herdr ]; then
  if [ "$status" = done ] && [ "$(cfg '.keep_done_tabs // false')" != true ]; then herdr tab close "$tab" >/dev/null 2>&1 || true
  else herdr notification show "$task: $key $status" --body "$summary" --sound request >/dev/null 2>&1 || true; fi
fi
echo "$key $status $summary"
[ "$status" = done ]
