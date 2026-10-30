#!/usr/bin/env bash
# task-init.sh <task-id>   create tasks/<id>/ skeleton + state.json (idempotent). Prints the task dir.
. "$(dirname "$0")/lib.sh"
id="${1:?task id}"; d="$ROOT/tasks/$id"
mkdir -p "$d"/research "$d"/work "$d"/artifacts
[ -f "$d/state.json" ] || jq -n --arg id "$id" --arg now "$(date -u +%FT%TZ)" '{
  task:$id,
  kind:(if ($id|test("^[A-Z][A-Z0-9]+-[0-9]+$")) then "jira" else "idea" end),
  created:$now,
  stages:{intake:"pending",research:"pending",plan:"pending",plan_review:"pending",grill:"pending"},
  repos:[], branch:null}' > "$d/state.json"
echo "$d"
