#!/usr/bin/env bash
# state.sh <task> get | next | set <stage> <status> | reset <stage> | update '<jq expr>' | wave-next
# Single writer = the lead. Workers never touch state.json (they write work/<key>.json).
# .stages holds intake..grill; `next` prints "waves" once those are done. Wave progress is never stored: `wave-next`
# derives it from work/<step>-<repo>.json (any -t<n> try counts when its status is done) and prints the first
# unfinished step as "<wave> <step> <repo...>" or "complete". Steps per wave, in order: execute, ui_test (the wave's
# frontend repos), code_review, ci_check, pr (key pr-w<wave>), merge (key merge-w<wave>, pr_mode merge only).
# `reset` of a wave step archives that step's and later steps' work files to work/stale-<time>/; reset of an
# earlier stage also archives every wave step's files.
. "$(dirname "$0")/lib.sh"
id="${1:?task}"; cmd="${2:?cmd}"; f="$ROOT/tasks/$id/state.json"; wd="$ROOT/tasks/$id/work"
[ -f "$f" ] || { echo "no state for $id (run task-init.sh)" >&2; exit 1; }
STEPS="execute ui_test code_review ci_check pr merge"
w() { jq "$@" "$f" > "$f.tmp" && mv "$f.tmp" "$f"; }

# done_key <key>: work/<key>.json or work/<key>-t<n>.json exists with status done.
done_key() {
  local g rest
  for g in "$wd/$1"*.json; do
    [ -f "$g" ] || continue
    rest=${g#"$wd/$1"}
    [[ "$rest" = .json || "$rest" =~ ^-t[0-9]+\.json$ ]] || continue
    [ "$(jq -r .status "$g")" = "done" ] && return 0
  done
  return 1
}

wave_next() {
  local meta mode wv repos fe st list need r
  meta=$(bash "$ROOT/scripts/plan-meta.sh" "$id") || exit 1
  mode=$(jq -r .pr_mode <<<"$meta")
  for wv in $(jq -r '.waves[].wave' <<<"$meta"); do
    repos=$(jq -r --argjson w "$wv" '.waves[] | select(.wave == $w) | .repos | join(" ")' <<<"$meta")
    fe=$(jq -r --argjson w "$wv" '(.waves[] | select(.wave == $w) | .repos) as $r | [.frontend[] | select(IN($r[]))] | join(" ")' <<<"$meta")
    for st in execute ui_test code_review ci_check; do
      list=$repos; [ "$st" = ui_test ] && list=$fe
      need=""; for r in $list; do done_key "$st-$r" || need="$need $r"; done
      [ -n "$need" ] && { echo "$wv $st$need"; return; }
    done
    done_key "pr-w$wv" || { echo "$wv pr $repos"; return; }
    [ "$mode" = merge ] && ! done_key "merge-w$wv" && { echo "$wv merge $repos"; return; }
  done
  echo complete
}

# archive_from <step>: move work files of <step> and every later wave step to work/stale-<time>/.
archive_from() {
  local arch on=0 s g
  arch="$wd/stale-$(date +%Y%m%d%H%M%S)"
  for s in $STEPS; do
    [ "$s" = "$1" ] && on=1
    [ $on = 1 ] || continue
    for g in "$wd/$s"-*.json; do [ -f "$g" ] && { mkdir -p "$arch"; mv "$g" "$arch/"; }; done
  done
  return 0
}

case "$cmd" in
  get)    jq -c . "$f" ;;
  next)   jq -r --arg steps "$STEPS" '($steps | split(" ")) as $s
            | [.stages | to_entries[] | select(.key | IN($s[]) | not) | select(.value != "done")][0].key // "waves"' "$f" ;;
  set)    w --arg s "${3:?stage}" --arg v "${4:?status}" '.stages[$s]=$v' ;;
  reset)  st="${3:?stage}"
          if [[ " $STEPS " == *" $st "* ]]; then archive_from "$st"
          else
            [ "$(jq --arg st "$st" '.stages | has($st)' "$f")" = true ] || { echo "unknown stage $st" >&2; exit 1; }
            w --arg st "$st" '(.stages|keys_unsorted) as $k | ($k|index($st)) as $i
              | .stages |= with_entries(. as $e | if ($k|index($e.key)) >= $i then .value="pending" else . end)'
            archive_from execute
          fi ;;
  update) w "${3:?jq expr}" ;;
  wave-next) wave_next ;;
  *) echo "bad cmd" >&2; exit 1 ;;
esac
