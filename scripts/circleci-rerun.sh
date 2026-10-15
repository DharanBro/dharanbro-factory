#!/usr/bin/env bash
# circleci-rerun.sh <org/repo> <job-number>  -> rerun failed jobs of that job's workflow (token from secrets.env, never printed)
. "$(dirname "$0")/lib.sh"
: "${CIRCLECI_TOKEN:?CIRCLECI_TOKEN not set}"
wf=$(curl -s -H "Circle-Token: $CIRCLECI_TOKEN" "https://circleci.com/api/v1.1/project/github/$1/$2" | jq -r '.workflows.workflow_id // empty')
[ -n "$wf" ] || { echo "no workflow for job $2" >&2; exit 1; }
curl -s -X POST -H "Circle-Token: $CIRCLECI_TOKEN" -H "Content-Type: application/json" -d '{"from_failed":true}' \
  "https://circleci.com/api/v2/workflow/$wf/rerun" | jq -c '{message, new_workflow: (.workflow_id // empty)}'
