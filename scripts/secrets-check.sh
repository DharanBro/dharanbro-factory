#!/usr/bin/env bash
# secrets-check.sh   Report which tokens are set (never prints values) and test them against the live APIs.
. "$(dirname "$0")/lib.sh"
chk() { printf '%-22s %s\n' "$1" "$2"; }
for v in ATLASSIAN_DOMAIN ATLASSIAN_EMAIL ATLASSIAN_API_TOKEN CIRCLECI_TOKEN; do chk "$v" "$([ -n "${!v:-}" ] && echo set || echo MISSING)"; done
[ -n "${ATLASSIAN_API_TOKEN:-}" ] && chk "atlassian auth" "HTTP $(curl -s -o /dev/null -w '%{http_code}' -u "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" "https://$ATLASSIAN_DOMAIN.atlassian.net/rest/api/3/myself")"
[ -n "${CIRCLECI_TOKEN:-}" ] && chk "circleci auth" "HTTP $(curl -s -o /dev/null -w '%{http_code}' -H "Circle-Token: $CIRCLECI_TOKEN" https://circleci.com/api/v2/me)"
exit 0
