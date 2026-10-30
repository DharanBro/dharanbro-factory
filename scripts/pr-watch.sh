#!/usr/bin/env bash
# pr-watch.sh <owner/repo#n>...      one line per PR state change; exit 0 when every PR is MERGED or CLOSED
# pr-watch.sh --repo <owner/name>    exit 0 once the repo exists (e.g. created by another PR)
# pr-watch.sh --file <path>          exit 0 once the file exists and is non-empty (e.g. work/grill.json)
# pr-watch.sh --npm <pkg@ver>...     exit 0 once every version is published (run from the repo dir: its .npmrc picks the registry)
# pr-watch.sh --self-test            offline checks of the classifier and the loop
# The lead's only way to wait. Run it detached and let Monitor tail the log (Monitor has a 30 min cap):
#   nohup bash <abs>/scripts/pr-watch.sh a/b#1 c/d#2 >> <task>/work/watch-<label>.log 2>&1 &
# Checks are judged on the latest run per check name, so a cancelled run superseded by a newer one is
# ignored. No checks yet for the head commit = PENDING, never GREEN (no gap right after a push).
# Exit 1 = bad args, 3 = cap hit (PR_WATCH_MAX_SEC, default 7200 = 2 h). Poll every PR_WATCH_INTERVAL s (60).
set -uo pipefail
interval="${PR_WATCH_INTERVAL:-60}"; max="${PR_WATCH_MAX_SEC:-7200}"

# gh pr view --json state,reviewDecision,headRefOid,statusCheckRollup on stdin -> one status line.
classify() {
  jq -r '
    def res: if (.conclusion // "") != "" then .conclusion elif (.state // "") != "" then .state else "PENDING" end;
    def final: IN("SUCCESS","NEUTRAL","SKIPPED","FAILURE","ERROR","TIMED_OUT","CANCELLED","ACTION_REQUIRED","STARTUP_FAILURE","STALE");
    ([.statusCheckRollup[]? | res as $r
       | {k: ((.workflowName // "") + "/" + (.name // .context // "?")), r: $r,
          t: (if ($r | final) then (.startedAt // .completedAt // "") else "9999" end)}]   # an unfinished run is the newest
     | group_by(.k) | map(max_by(.t))) as $c
    | [$c[] | select(.r | IN("FAILURE","ERROR","TIMED_OUT","CANCELLED","ACTION_REQUIRED","STARTUP_FAILURE")) | .k] as $bad
    | "\(.state) review=\(if (.reviewDecision // "") == "" then "NONE" else .reviewDecision end) checks="
      + (if ($c | length) == 0 then "PENDING(none-yet)"
         elif ($bad | length) > 0 then "FAILING(\($bad | join(",")))"
         elif any($c[]; .r | IN("SUCCESS","NEUTRAL","SKIPPED") | not) then "PENDING"
         else "GREEN" end)
      + " head=\((.headRefOid // "")[0:7])"'
}

capped() { [ "$SECONDS" -ge "$max" ] && { echo "TIMEOUT after ${max}s"; exit 3; }; return 0; }

watch_prs() {
  local -a prev=(); local i p s err open
  err=$(mktemp); trap 'rm -f "$err"' EXIT
  while :; do
    open=0; i=0
    for p in "$@"; do
      if s=$(gh pr view "${p##*#}" --repo "${p%%#*}" --json state,reviewDecision,headRefOid,statusCheckRollup 2>"$err"); then
        s=$(classify <<<"$s")
      else
        s="gh-error: $(tr '\n' ' ' <"$err" | cut -c1-300)"
      fi
      [ "$s" != "${prev[$i]:-}" ] && { echo "$p: $s"; prev[i]=$s; }
      case "$s" in MERGED*|CLOSED*) ;; *) open=1 ;; esac
      i=$((i + 1))
    done
    [ $open = 0 ] && { echo "ALL MERGED/CLOSED"; exit 0; }
    capped; sleep "$interval"
  done
}

watch_repo() {
  local e said=0
  until e=$(gh repo view "$1" --json name 2>&1 >/dev/null); do
    [ $said = 0 ] && { echo "$1: waiting for repo (gh: $(tr '\n' ' ' <<<"$e" | cut -c1-200))"; said=1; }
    capped; sleep "$interval"
  done
  echo "$1: REPO EXISTS"
}

watch_file() {
  echo "$1: waiting for file"
  until [ -s "$1" ]; do capped; sleep "$interval"; done
  echo "$1: FILE READY"
}

watch_npm() {
  local spec e said
  for spec in "$@"; do
    said=0
    until e=$(npm view "$spec" version 2>&1) && [ -n "$e" ]; do
      [ $said = 0 ] && { echo "$spec: waiting for publish (npm: $(tr '\n' ' ' <<<"$e" | cut -c1-200))"; said=1; }
      capped; sleep "$interval"
    done
    echo "$spec: PUBLISHED"
  done
}

self_test() {
  local d out fail=0
  ok() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got '$2' want '$3'"; fail=1; fi; }
  ok superseded-cancel "$(classify <<<'{"state":"OPEN","reviewDecision":"APPROVED","headRefOid":"abcdef123","statusCheckRollup":[
    {"workflowName":"ci","name":"test","status":"COMPLETED","conclusion":"CANCELLED","startedAt":"2026-10-30T10:00:00Z"},
    {"workflowName":"ci","name":"test","status":"COMPLETED","conclusion":"SUCCESS","startedAt":"2026-10-30T10:05:00Z"},
    {"context":"sonar","state":"SUCCESS"}]}')" "OPEN review=APPROVED checks=GREEN head=abcdef1"
  ok queued-rerun "$(classify <<<'{"state":"OPEN","reviewDecision":"","headRefOid":"abc","statusCheckRollup":[
    {"workflowName":"ci","name":"test","status":"COMPLETED","conclusion":"FAILURE","startedAt":"2026-10-30T10:00:00Z"},
    {"workflowName":"ci","name":"test","status":"QUEUED","conclusion":"","startedAt":"0001-01-01T00:00:00Z"}]}')" "OPEN review=NONE checks=PENDING head=abc"
  ok latest-fails "$(classify <<<'{"state":"OPEN","reviewDecision":null,"headRefOid":"abc","statusCheckRollup":[
    {"workflowName":"ci","name":"lint","status":"COMPLETED","conclusion":"SUCCESS","startedAt":"2026-10-30T10:00:00Z"},
    {"workflowName":"ci","name":"lint","status":"COMPLETED","conclusion":"FAILURE","startedAt":"2026-10-30T10:05:00Z"}]}')" "OPEN review=NONE checks=FAILING(ci/lint) head=abc"
  ok no-checks-yet "$(classify <<<'{"state":"OPEN","reviewDecision":"REVIEW_REQUIRED","headRefOid":"abc","statusCheckRollup":[]}')" \
    "OPEN review=REVIEW_REQUIRED checks=PENDING(none-yet) head=abc"
  # Loop with a fake gh: OPEN on the first poll, MERGED on the second; dedupes repeated states.
  d=$(mktemp -d)
  cat >"$d/gh" <<'EOF'
#!/usr/bin/env bash
[ "$1 $2" = "pr view" ] || { echo "unexpected: $*" >&2; exit 1; }
n=$(cat "$(dirname "$0")/n" 2>/dev/null || echo 0); echo $((n + 1)) >"$(dirname "$0")/n"
s=OPEN; [ "$n" -ge 2 ] && s=MERGED
echo "{\"state\":\"$s\",\"reviewDecision\":\"APPROVED\",\"headRefOid\":\"abc\",\"statusCheckRollup\":[{\"context\":\"ci\",\"state\":\"SUCCESS\"}]}"
EOF
  chmod +x "$d/gh"
  out=$(PATH="$d:$PATH" PR_WATCH_INTERVAL=0 bash "$0" o/r#1 2>&1)
  ok loop "$out" "o/r#1: OPEN review=APPROVED checks=GREEN head=abc
o/r#1: MERGED review=APPROVED checks=GREEN head=abc
ALL MERGED/CLOSED"
  ok bad-arg "$(bash "$0" not-a-pr 2>&1; echo "rc=$?")" "bad PR ref 'not-a-pr' (want owner/repo#n)
rc=1"
  : >"$d/f"; echo x >"$d/f2"
  ok cap "$(PR_WATCH_INTERVAL=0 PR_WATCH_MAX_SEC=0 bash "$0" --file "$d/f" 2>&1; echo "rc=$?")" "$d/f: waiting for file
TIMEOUT after 0s
rc=3"
  ok file "$(bash "$0" --file "$d/f2" 2>&1 | tail -1)" "$d/f2: FILE READY"
  cat >"$d/npm" <<'EOF'
#!/usr/bin/env bash
[ "$2" = "@s/p@2.0.0" ] && echo 2.0.0
EOF
  chmod +x "$d/npm"
  ok npm "$(PATH="$d:$PATH" bash "$0" --npm "@s/p@2.0.0" 2>&1)" "@s/p@2.0.0: PUBLISHED"
  rm -rf "$d"
  return $fail
}

# Unquoted $* flattens args: zsh passes "a/b#1 c/d#2" as one. Refs never contain spaces.
# shellcheck disable=SC2048,SC2086
case "${1:-}" in
  --self-test) self_test; exit ;;
  --repo) watch_repo "${2:?owner/name}" ;;
  --file) watch_file "${2:?path}" ;;
  --npm) shift; set -- $*; [ $# -gt 0 ] || { echo "--npm needs pkg@ver" >&2; exit 1; }; watch_npm "$@" ;;
  "") echo "usage: pr-watch.sh <owner/repo#n>... | --repo <owner/name> | --file <path> | --npm <pkg@ver>... | --self-test" >&2; exit 1 ;;
  *)
    set -- $*
    for p in "$@"; do
      [[ "$p" =~ ^[^/#[:space:]]+/[^/#[:space:]]+#[0-9]+$ ]] || { echo "bad PR ref '$p' (want owner/repo#n)" >&2; exit 1; }
    done
    watch_prs "$@" ;;
esac
