#!/usr/bin/env bash
# Shared helpers. Source me: . "$(dirname "$0")/lib.sh"
set -euo pipefail
ROOT="${FACTORY_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# Tokens for every script; hosted workers start fresh shells.
[ -f "$ROOT/secrets.env" ] && { set -a; . "$ROOT/secrets.env"; set +a; }

yml2json() { ruby --disable-gems -ryaml -rjson -e 'puts JSON.generate(YAML.load_file(ARGV[0]) || {})' "$1"; }

# merged config: factory.yml overlaid by tasks/<id>/factory.override.yml (if any)
conf() {
  local id="${1:-}" base
  base=$(yml2json "$ROOT/factory.yml")
  if [ -n "$id" ] && [ -f "$ROOT/tasks/$id/factory.override.yml" ]; then
    jq -s '.[0] * .[1]' <(echo "$base") <(yml2json "$ROOT/tasks/$id/factory.override.yml")
  else
    echo "$base"
  fi
}

repos_json() { if [ -f "$ROOT/repos.yml" ]; then yml2json "$ROOT/repos.yml"; else echo '{"repos":{}}'; fi; }

# herdr-safe agent name: [a-z][a-z0-9_-]{0,31}, stable + unique via short hash when truncated
norm() {
  local s h
  s=$(printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9_\n-' '-')
  case "$s" in [a-z]*) ;; *) s="f-$s" ;; esac
  if [ ${#s} -gt 32 ]; then
    h=$(printf '%s' "$1" | shasum | cut -c1-4)
    s="${s:0:27}-$h"
  fi
  printf '%s' "$s"
}

# runner: herdr | hc | headless. herdr and auto follow the app you launch from: a pane of the
# `herdr` daemon (Herdr UI / TUI) -> herdr, a terminal of the new Herdr app (herdr-core) -> hc.
# Outside both, herdr stays on the daemon and auto falls back to headless.
runner() {
  local r; r=$(conf "${1:-}" | jq -r '.runner // "auto"')
  if [ "$r" = auto ] || [ "$r" = herdr ]; then
    if [ "${HERDR_ENV:-}" = 1 ] && command -v herdr >/dev/null 2>&1; then r=herdr
    elif [ -n "${HC_TERMINAL_ID:-}" ] && command -v hc >/dev/null 2>&1; then r=hc
    elif [ "$r" = auto ]; then r=headless; fi
  fi
  echo "$r"
}

# The new Herdr app's window CLI (spaces, tabs, focus). Not on PATH by default on macOS.
herdr_app() {
  local a="${HERDR_APP_BIN:-$(command -v herdr-app 2>/dev/null || true)}"
  if [ -z "$a" ]; then
    a=$(mdfind "kMDItemCFBundleIdentifier == 'dev.herdr.app'" 2>/dev/null | head -1); a="${a:+$a/Contents/MacOS/Herdr}"
  fi
  [ -n "$a" ] || return 1
  "$a" "$@"
}

# notify <runner> <title> <body>: the herdr daemon's notification, else a desktop one.
notify() {
  if [ "$1" = herdr ]; then herdr notification show "$2" --body "$3" --sound request >/dev/null 2>&1 || true
  else osascript -e 'on run a' -e 'display notification (item 2 of a) with title (item 1 of a) sound name "Glass"' -e 'end run' "$2" "$3" >/dev/null 2>&1 || true; fi
}

# hc terminal state: idle|working|done|blocked|error|starting (no status yet)|finished|gone
hc_state() { hc get "$1" --json 2>/dev/null | jq -r 'if .state == "live" then .status.state // "starting" else "finished" end' || echo gone; }

# hc_spawn <name> <space> <task> <tab> <cwd> <prompt> <cmd...>: start an agent as an hc terminal that the
# new Herdr app shows as tab <tab> in <space>, then submit the prompt once it is idle.
# Startup dialogs remain visible for the user to resolve.
hc_spawn() {
  local name="$1" space="$2" task="$3" tab="$4" cwd="$5" prompt="$6" i s tb deadline notified=0; shift 6
  hc run --bg --name "$name" --no-parent --no-notify --cwd "$cwd" ${space:+--label "herdr.space=$space"} \
    --label "factory.task=$task" --label "factory.tab=$tab" -- "$@" >/dev/null || { echo "hc run failed" >&2; return 1; }
  for i in 1 2 3 4 5; do   # the app numbers new tabs; name it after the worker key
    tb=$(herdr_app ls 2>/dev/null | jq -r --arg n "$name" '.spaces[].tabs[] | select(any(.terminals[]; .name == $n)) | .id' 2>/dev/null || true)
    [ -n "$tb" ] && { herdr_app "do" tab.rename --id "$tb" --name "$tab" >/dev/null 2>&1 || true; break; }
    sleep 1
  done
  deadline=$(( $(date +%s) + 600 ))
  until s=$(hc_state "$name"); [ "$s" = idle ] && hc send "$name" "$prompt" >/dev/null 2>&1; do
    case "$s" in
      finished|gone) echo "agent exited at startup" >&2; return 1 ;;
      blocked) [ $notified = 1 ] || { notify hc "Worker blocked at startup" "Open tab '$tab' and answer the dialog"; notified=1; } ;;
    esac
    [ "$(date +%s)" -gt "$deadline" ] && { echo "worker never became ready" >&2; return 1; }
    sleep 2
  done
  # Same guard as herdr_spawn: a pasted prompt left unsubmitted keeps the agent idle.
  for i in 1 2 3; do
    sleep 6
    [ "$(hc_state "$name")" = idle ] || return 0
    hc keys "$name" enter >/dev/null 2>&1 || true
  done
}

# Resolve a stage's effective harness and its keyed profile.
stage_agent() {
  jq -r --arg stage "$2" '.agent_override // .stages[$stage].default // empty' <<<"$1"
}

stage_model() {
  jq -r --arg stage "$2" --arg agent "$3" '.stages[$stage].agents[$agent].model // empty' <<<"$1"
}

stage_effort() {
  jq -r --arg stage "$2" --arg agent "$3" '.stages[$stage].agents[$agent].effort // empty' <<<"$1"
}

# Expand agent CLI argument placeholders without invoking a shell.
agent_arg() {
  local value="$1"
  value="${value//\{root\}/$ROOT}"
  value="${value//\{task_dir\}/$2}"
  value="${value//\{cwd\}/$3}"
  value="${value//\{model\}/$4}"
  value="${value//\{effort\}/$5}"
  printf '%s' "$value"
}

# Start a configured agent in an existing Herdr pane and submit the prompt.
# Startup dialogs remain visible for the user to resolve.
herdr_spawn() {
  local kind="$1" name="$2" pane="$3" prompt="$4" i deadline notified=0; shift 4
  [ -n "$kind" ] || { echo "agent.herdr.kind is required" >&2; return 1; }
  for i in 1 2 3 4 5; do
    herdr agent start "$name" --kind "$kind" --pane "$pane" --timeout 30000 -- "$@" >/dev/null 2>&1 && break
    herdr agent get "$name" >/dev/null 2>&1 && break      # started but blocked at a startup dialog
    [ "$i" = 5 ] && { echo "agent start failed" >&2; return 1; }
    sleep 2
  done
  deadline=$(( $(date +%s) + 600 ))
  until herdr agent prompt "$name" "$prompt" >/dev/null 2>&1; do
    [ $notified = 1 ] || { notify herdr "Worker blocked at startup" "Open tab '$name' and answer the dialog"; notified=1; }
    [ "$(date +%s)" -gt "$deadline" ] && { echo "worker never became ready" >&2; return 1; }
    sleep 4
  done
  # A long prompt can land in the input box without being submitted, leaving the worker idle
  # forever. If it is still idle after a few seconds, press Enter (max 3 times).
  for i in 1 2 3; do
    sleep 6
    herdr agent get "$name" 2>/dev/null | grep -q '"idle"' || return 0
    herdr pane send-keys "$pane" Enter >/dev/null 2>&1 || true
  done
}
