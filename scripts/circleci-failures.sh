#!/usr/bin/env bash
# circleci-failures.sh <org/repo> <job-number>  -> failed tests + tail of failed step logs (token from secrets.env, never printed)
. "$(dirname "$0")/lib.sh"
: "${CIRCLECI_TOKEN:?CIRCLECI_TOKEN not set}"
slug="$1"; n="$2"; H="Circle-Token: $CIRCLECI_TOKEN"
echo "## failed tests"
curl -s -H "$H" "https://circleci.com/api/v2/project/gh/$slug/$n/tests" \
  | jq -r '.items[]? | select(.result=="failure") | "\(.classname) :: \(.name)\n\(.message // "" | .[0:600])"' | head -60
echo "## failed steps"
curl -s -H "$H" "https://circleci.com/api/v1.1/project/github/$slug/$n" \
  | jq -r '.steps[]?.actions[]? | select(.failed==true or .status=="failed") | "\(.name)\t\(.output_url // "")"' | while IFS=$'\t' read -r name url; do
    echo "--- $name"; [ -n "$url" ] && curl -s "$url" | jq -r '.[0].message // empty' | tail -n 60
  done
