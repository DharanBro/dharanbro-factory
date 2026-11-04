#!/usr/bin/env bash
# circleci-step-log.sh <org/repo> <job-number> <step-name-regex> [lines]  -> tail of matching step logs (token from secrets.env, never printed)
. "$(dirname "$0")/lib.sh"
: "${CIRCLECI_TOKEN:?CIRCLECI_TOKEN not set}"
slug="$1"; n="$2"; re="$3"; lines="${4:-200}"
H="Circle-Token: $CIRCLECI_TOKEN"
curl -s -H "$H" "https://circleci.com/api/v1.1/project/github/$slug/$n" \
  | jq -r --arg re "$re" '.steps[]?.actions[]? | select(.name | test($re; "i")) | "\(.name)\t\(.output_url // "")"' | while IFS=$'\t' read -r name url; do
    echo "--- $name"; [ -n "$url" ] && curl -s "$url" | jq -r '.[0].message // empty' | tr -d '\r' | tail -n "$lines"   # CircleCI lines end in \r (DP-8112 retro)
  done
