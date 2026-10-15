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

# runner: herdr | headless (auto uses Herdr only inside Herdr)
runner() {
  local r; r=$(conf "${1:-}" | jq -r '.runner // "auto"')
  if [ "$r" = auto ]; then
    if [ "${HERDR_ENV:-}" = 1 ] && command -v herdr >/dev/null 2>&1; then r=herdr; else r=headless; fi
  fi
  echo "$r"
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
    if [ $notified = 0 ]; then
      herdr notification show "Worker blocked at startup" --body "Open tab '$name' and answer the dialog" --sound request >/dev/null 2>&1 || true; notified=1
    fi
    [ "$(date +%s)" -gt "$deadline" ] && { echo "worker never became ready" >&2; return 1; }
    sleep 4
  done
}
