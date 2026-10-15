#!/usr/bin/env bash
# jira-attach.sh <ISSUE-KEY> <file>...   Attach files to a Jira issue via REST (the Atlassian MCP cannot upload).
# Needs ATLASSIAN_DOMAIN / ATLASSIAN_EMAIL / ATLASSIAN_API_TOKEN from secrets.env.
. "$(dirname "$0")/lib.sh"
issue="${1:?issue key}"; shift; [ $# -gt 0 ] || { echo "no files" >&2; exit 1; }
: "${ATLASSIAN_API_TOKEN:?set ATLASSIAN_API_TOKEN in secrets.env}" "${ATLASSIAN_DOMAIN:?}" "${ATLASSIAN_EMAIL:?}"
for f in "$@"; do
  [ -f "$f" ] || { echo "missing $f" >&2; exit 1; }
  curl -sf -u "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" -H "X-Atlassian-Token: no-check" -F "file=@$f" \
    "https://$ATLASSIAN_DOMAIN.atlassian.net/rest/api/3/issue/$issue/attachments" | jq -r '.[0]|"attached \(.filename) (\(.size) B) to '"$issue"'"'
done
