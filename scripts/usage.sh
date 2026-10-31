#!/usr/bin/env bash
# Token usage per worker and per task, read from the agents' own session logs.
#   usage.sh log <task> <key> <agent> <run-id> <stamp-file>   (run-stage.sh) -> tasks/<task>/work/<key>.usage.json
#   usage.sh report <task>                                    table of every worker + lead, with totals
# Logs are matched by a marker string that the worker prompt contains (RUN=<id>), so no agent flags are needed.
# Columns: input = fresh input, cached = cache reads, cache_write = cache writes (Claude only), output = output
# (incl. reasoning). Codex reports cached as a subset of input; it is split out here so the columns never overlap.
. "$(dirname "$0")/lib.sh"
CLAUDE_LOGS="${CLAUDE_LOGS:-$HOME/.claude/projects}"; CODEX_LOGS="${CODEX_LOGS:-$HOME/.codex/sessions}"

# first_prompt_has <file> <marker>: the marker is in the session's first prompt. A lead's log also holds worker
# prompts (Herdr output), so a match anywhere in the file would bill the lead's turns to a worker.
first_prompt_has() {
  local p
  p=$(jq -cn 'first(inputs | select(.type=="user" and (.isMeta|not) and (.message.content|type)=="string") | .message.content)' "$1" 2>/dev/null) || return 1
  [[ "$p" == *"$2"* ]]
}

# find_logs <agent> <marker> [newer-than-file]: session logs whose first prompt contains the marker
find_logs() {
  local dir=$CLAUDE_LOGS f
  [ "$1" = codex ] && dir=$CODEX_LOGS
  [ -d "$dir" ] || return 0
  find "$dir" -name '*.jsonl' -not -path '*/subagents/*' ${3:+-newer "$3"} -print0 | xargs -0 grep -lF -- "$2" 2>/dev/null |
    while IFS= read -r f; do
      # ponytail: Codex logs still match anywhere; give them a first-prompt check when a Codex lead runs.
      [ "$1" = claude ] && ! first_prompt_has "$f" "$2" && continue
      echo "$f"
      [ "$1" = claude ] && ls "${f%.jsonl}"/subagents/*.jsonl 2>/dev/null   # subagent usage is logged in separate files
    done || true
}

# sum_usage <agent> <file...>: one JSON object {model,input,cached,cache_write,output,total}
sum_usage() {
  local agent=$1; shift
  if [ "$agent" = codex ]; then
    for f in "$@"; do   # token_count totals are cumulative per session: take the last one
      jq -s '{model:([.[]|select(.type=="turn_context")|.payload.model][0] // "?"),
              u:([.[]|select(.type=="event_msg" and .payload.type=="token_count")|.payload.info.total_token_usage]|last // {})}' "$f"
    done | jq -s '{model:(.[0].model // "?"),
      input:(map((.u.input_tokens // 0) - (.u.cached_input_tokens // 0))|add // 0),
      cached:(map(.u.cached_input_tokens // 0)|add // 0), cache_write:(map(.u.cache_write_input_tokens // 0)|add // 0),
      output:(map(.u.output_tokens // 0)|add // 0)}'
  else   # a reply is logged once per content block with the same id: keep the last copy of each
    [ $# -gt 0 ] && jq -s '[.[]|select(.type=="assistant" and .message.usage and .message.model != "<synthetic>")|{id:.message.id,m:.message.model,u:.message.usage}]
      |reverse|unique_by(.id) as $r | {model:($r[0].m // "?"),
      input:($r|map(.u.input_tokens // 0)|add // 0), cached:($r|map(.u.cache_read_input_tokens // 0)|add // 0),
      cache_write:($r|map(.u.cache_creation_input_tokens // 0)|add // 0), output:($r|map(.u.output_tokens // 0)|add // 0)}' "$@" ||
      echo '{"model":"?","input":0,"cached":0,"cache_write":0,"output":0}'
  fi | jq -c '.+{total:(.input+.cached+.cache_write+.output)}'
}

case "${1:-}" in
  log)
    task=${2:?}; key=${3:?}; agent=${4:?}; run=${5:?}; stamp=${6:-}
    files=(); while IFS= read -r f; do files+=("$f"); done < <(find_logs "$agent" "RUN=$run" "$stamp")
    [ ${#files[@]} -gt 0 ] || { echo "no $agent log found for RUN=$run" >&2; exit 0; }
    jq -n --arg k "$key" --arg a "$agent" --argjson u "$(sum_usage "$agent" "${files[@]}")" '{key:$k,agent:$a}+$u' \
      > "$ROOT/tasks/$task/work/$key.usage.json" ;;
  report)
    task=${2:?}; w="$ROOT/tasks/$task/work"; rows=$(mktemp)
    cat "$w"/*.usage.json 2>/dev/null > "$rows" || true
    # The lead may span several sessions; its prompt carries this fixed phrase.
    for agent in claude codex; do
      files=(); while IFS= read -r f; do files+=("$f"); done < <(find_logs "$agent" "in LEAD mode. TASK=$task ")
      [ ${#files[@]} -gt 0 ] && jq -n --arg a "$agent" --argjson u "$(sum_usage "$agent" "${files[@]}")" '{key:"lead",agent:$a}+$u' >> "$rows"
    done
    jq -rs '(["KEY","AGENT","MODEL","INPUT","CACHED","CACHE_W","OUTPUT","TOTAL"],
             (sort_by(.key)[]|[.key,.agent,.model,.input,.cached,.cache_write,.output,.total]),
             ["TOTAL","-","-",(map(.input)|add // 0),(map(.cached)|add // 0),(map(.cache_write)|add // 0),(map(.output)|add // 0),(map(.total)|add // 0)])
            |@tsv' "$rows" | column -t -s $'\t'
    rm -f "$rows" ;;
  *) echo "usage: usage.sh log <task> <key> <agent> <run-id> <stamp> | report <task>" >&2; exit 1 ;;
esac
