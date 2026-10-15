#!/usr/bin/env bash
# circleci-branch.sh <org/repo> <branch> [n]  -> recent pipelines' "Run Unit Tests" status on a branch
. "$(dirname "$0")/lib.sh"; : "${CIRCLECI_TOKEN:?}"
curl -s -H "Circle-Token: $CIRCLECI_TOKEN" "https://circleci.com/api/v1.1/project/github/$1/tree/$2?limit=${3:-30}&filter=completed" \
  | jq -r '.[] | select(.workflows.job_name|test("Unit Tests";"i")) | "\(.build_num) \(.status) \(.stop_time[0:16]) \(.subject[0:60])"'
