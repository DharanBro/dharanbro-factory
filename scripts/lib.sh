#!/usr/bin/env bash
# Shared helpers. Source me: . "$(dirname "$0")/lib.sh"
set -euo pipefail
ROOT="${FACTORY_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# tokens (Atlassian, CircleCI...) for every script; herdr tabs start fresh shells, so scripts load them themselves
[ -f "$ROOT/secrets.env" ] && { set -a; . "$ROOT/secrets.env"; set +a; }

yml2json() { ruby -ryaml -rjson -e 'puts JSON.generate(YAML.load_file(ARGV[0]) || {})' "$1"; }

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

# runner: herdr | headless (config runner=auto picks herdr only when inside Herdr)
runner() {
  local r; r=$(conf "${1:-}" | jq -r '.runner // "auto"')
  if [ "$r" = auto ]; then [ "${HERDR_ENV:-}" = 1 ] && r=herdr || r=headless; fi
  echo "$r"
}

# herdr_spawn <name> <pane> <prompt> <claude args...>
# Start a claude agent in an existing shell pane, then submit the prompt once it is ready.
# New worktrees are separate git roots, so claude shows a one-time "trust this folder" dialog there.
# With AUTO_TRUST=true (factory.yml auto_trust_worktrees) the factory answers it for folders it created itself.
# Any other startup dialog: notify the user and keep retrying the prompt until it is answered.
herdr_spawn() {
  local name="$1" pane="$2" prompt="$3" i deadline txt notified=0; shift 3
  for i in 1 2 3 4 5; do
    herdr agent start "$name" --kind claude --pane "$pane" --timeout 30000 -- "$@" >/dev/null 2>&1 && break
    herdr agent get "$name" >/dev/null 2>&1 && break      # started but blocked at a startup dialog
    [ "$i" = 5 ] && { echo "agent start failed" >&2; return 1; }
    sleep 2
  done
  deadline=$(( $(date +%s) + 600 ))
  until herdr agent prompt "$name" "$prompt" >/dev/null 2>&1; do
    txt=$(herdr agent read "$name" --source visible --lines 30 2>/dev/null || true)
    if [ "${AUTO_TRUST:-true}" = true ] && grep -q 'trust this folder' <<<"$txt"; then
      grep -q '❯ No' <<<"$txt" && herdr agent send-keys "$name" down >/dev/null 2>&1
      herdr agent send-keys "$name" enter >/dev/null 2>&1
    elif [ $notified = 0 ]; then
      herdr notification show "Worker blocked at startup" --body "Open tab '$name' and answer the dialog" --sound request >/dev/null 2>&1 || true; notified=1
    fi
    [ "$(date +%s)" -gt "$deadline" ] && { echo "worker never became ready" >&2; return 1; }
    sleep 4
  done
}
