#!/usr/bin/env bash
# sonar-scan.sh <task> <repo> | sonar-scan.sh prune
# Scan a task's worktree on the local factory-sonar (gate + rules mirrored by sonar-sync.sh) and write
# artifacts/sonar-<repo>.md. One Sonar project per task (`<key>--<task>`) because Community has no branch analysis:
#   1. base analysis = merge-base content, back-dated to the merge-base commit time (sonar.projectDate)
#   2. new-code period = that analysis -> "new code" = exactly the lines this branch changed (SCM blame dates)
#   3. head analysis = the worktree, gate evaluated on new code
# Exit 0 = no issues on branch-changed lines, 1 = issues on branch-changed lines, 2 = not configured / server unreachable / scan failed (report as UNVERIFIED).
# Task projects + scanner work dirs older than $SONAR_KEEP_DAYS (7) are deleted on every run (`prune` = only that).
. "$(dirname "$0")/lib.sh"
LOCAL="${SONAR_LOCAL_URL:-http://localhost:9100}"; KEEP_DAYS="${SONAR_KEEP_DAYS:-7}"
ENVF="$ROOT/sonar/local.env"
[ -f "$ENVF" ] || { echo "no $ENVF (run scripts/sonar-sync.sh first)" >&2; exit 2; }
. "$ENVF"
L() { curl -sf -u "$SONAR_LOCAL_TOKEN:" "$@"; }

up() { [ "$(curl -s "$LOCAL/api/system/status" | jq -r .status 2>/dev/null)" = UP ]; }
up || { docker start factory-sonar >/dev/null 2>&1; for _ in $(seq 24); do up && break; sleep 5; done; }
up || { echo "local sonar not reachable at $LOCAL" >&2; exit 2; }

prune() {
  # `--` only appears in task project keys, never in the base projects sonar-sync.sh creates
  L -X POST "$LOCAL/api/projects/bulk_delete" -d "q=--" \
    --data-urlencode "analyzedBefore=$(date -u -v-"${KEEP_DAYS}"d +%Y-%m-%dT%H:%M:%S%z)" >/dev/null || true
  find "$ROOT/sonar/work" -mindepth 1 -maxdepth 1 -mtime +"$KEEP_DAYS" -exec rm -rf {} + 2>/dev/null || true
}
mkdir -p "$ROOT/sonar/work"; prune
[ "${1:-}" = prune ] && { echo "pruned task projects older than ${KEEP_DAYS}d"; exit 0; }

task="${1:?}"; repo="${2:?}"
key=$(repos_json | jq -r --arg r "$repo" '.repos[$r].sonar.project_key // empty')
[ -n "$key" ] || { echo "no sonar.project_key for $repo" >&2; exit 2; }
covcmd=$(repos_json | jq -r --arg r "$repo" '.repos[$r].sonar.coverage_cmd // empty')
base=$(repos_json | jq -r --arg r "$repo" '.repos[$r].branch // "main"')
wt="$ROOT/tasks/$task/$repo"; snap="$ROOT/sonar/$repo"; out="$ROOT/tasks/$task/artifacts/sonar-$repo.md"
[ -d "$wt" ] || { echo "no worktree $wt" >&2; exit 1; }
[ -f "$snap/gate.json" ] || { echo "no snapshot $snap (run sonar-sync.sh)" >&2; exit 2; }
K="$key--$task"; W="$ROOT/sonar/work/$K"; mkdir -p "$W" "$(dirname "$out")"

scan() {  # scan <dir> <workdir> [extra -D...]  (CLI -D overrides the repo's sonar-project.properties host/key)
  local d="$1" w="$2"; shift 2; mkdir -p "$w"
  ( cd "$d" && sonar-scanner -Dsonar.host.url="$LOCAL" -Dsonar.token="$SONAR_LOCAL_TOKEN" -Dsonar.projectKey="$K" \
      -Dsonar.projectName="$K" -Dsonar.working.directory="$w" "$@" ) > "$w.log" 2>&1
}

mb=$(git -C "$wt" merge-base HEAD "origin/$base")
bdate=$(TZ=UTC git -C "$wt" show -s --date=format-local:%Y-%m-%dT%H:%M:%S%z --format=%cd "$mb")

# base analysis: skip when this project already has one at the same merge-base
have=$(L "$LOCAL/api/project_analyses/search?project=$K" 2>/dev/null | jq -r --arg mb "$mb" '[.analyses[]?|select(.projectVersion=="base" and .revision==$mb)]|length' || true)
if [ "${have:-0}" -eq 0 ]; then
  L -X POST "$LOCAL/api/projects/delete" -d "project=$K" >/dev/null 2>&1 || true
  L -X POST "$LOCAL/api/projects/create" -d "project=$K" --data-urlencode "name=$K" >/dev/null
  gate=$(jq -r .name "$snap/gate.json")
  L -X POST "$LOCAL/api/qualitygates/select" --data-urlencode "gateName=$gate" -d "projectKey=$K" >/dev/null
  jq -c '.profiles[]|select((.isBuiltIn|not) and (.language|IN("js","ts","css","web","xml","docker")))' "$snap/profiles.json" | while read -r p; do
    L -X POST "$LOCAL/api/qualityprofiles/add_project" --data-urlencode "qualityProfile=$(jq -r .name <<<"$p")" \
      -d "language=$(jq -r .language <<<"$p")" -d "project=$K" >/dev/null
  done
  bwt="$ROOT/sonar/work/$K-base-src"; rm -rf "$bwt"; git -C "$wt" worktree add -q --detach "$bwt" "$mb"
  scan "$bwt" "$W/base" -Dsonar.projectVersion=base -Dsonar.projectDate="$bdate" -Dsonar.qualitygate.wait=true && brc=0 || brc=$?
  git -C "$wt" worktree remove --force "$bwt" 2>/dev/null || rm -rf "$bwt"
  [ $brc -eq 0 ] || grep -q "Analysis report uploaded" "$W/base.log" || { echo "base scan failed, see $W/base.log" >&2; exit 2; }
  akey=$(L "$LOCAL/api/project_analyses/search?project=$K" | jq -r '.analyses[]|select(.projectVersion=="base")|.key' | head -1)
  L -X POST "$LOCAL/api/new_code_periods/set" -d "project=$K" -d type=SPECIFIC_ANALYSIS -d "value=$akey" >/dev/null
fi

# optional coverage (lcov path comes from the repo's own sonar-project.properties); failures only lose coverage data
[ -z "$covcmd" ] || ( cd "$wt" && bash -c "$covcmd" ) > "$W/coverage.log" 2>&1 || echo "coverage_cmd failed (see $W/coverage.log)" >&2

scan "$wt" "$W/head" -Dsonar.projectVersion=head -Dsonar.qualitygate.wait=true || true   # gate failure also exits non-zero; verdict read below
grep -q "Analysis report uploaded" "$W/head.log" || { echo "head scan failed:" >&2; tail -n 15 "$W/head.log" >&2; exit 2; }

st=$(L "$LOCAL/api/qualitygates/project_status?projectKey=$K")
gstatus=$(jq -r .projectStatus.status <<<"$st")
# Verdict = issues on lines THIS BRANCH added/changed (git diff vs merge-base). The server gate also counts whole-project
# conditions and the new-code baseline can include untouched files, so it is reported for information only.
L "$LOCAL/api/issues/search?componentKeys=$K&inNewCodePeriod=true&resolved=false&ps=500&s=SEVERITY&asc=false" > "$W/issues.json"
git -C "$wt" diff -U0 --no-color "$mb" HEAD > "$W/branch.diff"
mine=$(python3 -I "$ROOT/scripts/sonar_changed_issues.py" "$W/issues.json" "$W/branch.diff")
[ -n "$mine" ] && status=ERROR || status=OK
{
  echo "# sonar: $repo ($(date -u +%FT%TZ))"; echo
  echo "Verdict **$status**: $([ -n "$mine" ] && echo "$(wc -l <<<"$mine" | tr -d ' ') issue(s) on lines changed by this branch" || echo "no issues on lines changed by this branch"). Server gate (whole project, info only): $gstatus. Dashboard: $LOCAL/dashboard?id=$K"; echo
  echo "## Issues on branch changes"
  [ -n "$mine" ] && echo "$mine" || echo "- none"
  echo; echo "## Server gate conditions (info only, may include untouched code)"
  jq -r '.projectStatus.conditions[]|select(.status=="ERROR")|"- \(.metricKey): \(.actualValue) (fails when \(.comparator) \(.errorThreshold))"' <<<"$st"
  echo; echo "## Coverage"
  [ -n "$covcmd" ] || echo "- no sonar.coverage_cmd for $repo: coverage conditions only valid if the worker generated lcov before this run"
  grep -q "No coverage information will be saved" "$W/head.log" && echo "- lcov report NOT found: new_coverage conditions above are not meaningful" || true
} > "$out"
echo "$status  $out"
[ "$status" = OK ]
