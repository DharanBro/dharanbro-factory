#!/usr/bin/env bash
# jira.sh get <KEY>              the ticket as compact markdown: summary, type, status, labels, description,
#                                acceptance-criteria fields, last 5 comments, linked issues, remote links.
#                                Jira text stays wiki markup ("# item" = numbered list), fenced so it never reads as a heading.
# jira.sh comment <KEY> <file>   add the file's text as one comment (Jira wiki markup)
# Jira REST with ATLASSIAN_* from secrets.env, so workers need no Jira MCP. Never prints the token.
. "$(dirname "$0")/lib.sh"
: "${ATLASSIAN_API_TOKEN:?set ATLASSIAN_API_TOKEN in secrets.env}" "${ATLASSIAN_DOMAIN:?}" "${ATLASSIAN_EMAIL:?}"
api() { curl -sSf -u "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" -H "Content-Type: application/json" "$@"; }
cmd="${1:-}"; key="${2:?usage: jira.sh get <KEY> | comment <KEY> <file>}"
url="https://$ATLASSIAN_DOMAIN.atlassian.net/rest/api/2/issue/$key"
case "$cmd" in
  get)
    api "$url?expand=names" | jq -r '.names as $n | .fields as $f
      | "# \(.key): \($f.summary)",
        "Type: \($f.issuetype.name) | Status: \($f.status.name) | Labels: \(($f.labels // []) | join(", "))\(if $f.parent then " | Parent: \($f.parent.key)" else "" end)",
        "", "## Description", "```", ($f.description // "-"), "```",
        ($n | to_entries[] | select(.value | test("acceptance"; "i")) | select($f[.key] != null)
          | "", "## \(.value)", "```", ($f[.key] | if type == "string" then . else tojson end), "```"),
        "", "## Comments (last 5)", ((($f.comment.comments // [])[-5:])[] | "- \(.author.displayName) (\(.created[0:10])):", "```", .body, "```"),
        "", "## Linked issues", (($f.issuelinks // [])[] | (.outwardIssue // .inwardIssue) as $i
          | "- \(if .outwardIssue then .type.outward else .type.inward end) \($i.key): \($i.fields.summary)")'
    api "$url/remotelink" | jq -r '"", "## Remote links", (.[] | "- \(.object.title): \(.object.url)")' ;;
  comment)
    f="${3:?file}"; [ -f "$f" ] || { echo "missing $f" >&2; exit 1; }
    jq -n --rawfile b "$f" '{body: $b}' | api -X POST --data @- "$url/comment" | jq -r --arg k "$key" '"commented on \($k) (id \(.id))"' ;;
  *) echo "usage: jira.sh get <KEY> | comment <KEY> <file>" >&2; exit 1 ;;
esac
