#!/usr/bin/env bash
# usage.sh: a session counts only when the marker is in its first prompt. The lead's log also echoes worker prompts
# (Herdr output); before the fix those lead turns were billed to the worker.
. "$(dirname "$0")/lib.sh"
R=$(fake_root usage.sh); L="$R/logs/proj"; mkdir -p "$L" "$R/tasks/t/work"
msg() { jq -cn --arg c "$1" '{type:"user",message:{content:$c}}'; }
turn() { jq -cn --arg id "$1" --argjson n "$2" '{type:"assistant",message:{id:$id,model:"m",usage:{input_tokens:$n,cache_read_input_tokens:0,cache_creation_input_tokens:0,output_tokens:0}}}'; }
{ msg "Follow skill. TASK=t KEY=execute-a RUN=R1 go"; turn w1 10; } > "$L/worker.jsonl"
{ msg "Follow lead.md in LEAD mode. TASK=t ROOT=x"; turn l1 1000
  jq -cn '{type:"user",message:{content:[{type:"tool_result",content:"herdr: prompt ... RUN=R1 ..."}]}}'; turn l2 2000; } > "$L/lead.jsonl"
u() { CLAUDE_LOGS="$R/logs" FACTORY_ROOT="$R" bash "$R/scripts/usage.sh" "$@"; }
u log t execute-a claude R1 ""
ok worker-only "$(jq .total "$R/tasks/t/work/execute-a.usage.json")" 10
ok lead-row "$(u report t | awk '$1=="lead"{print $8}')" 3000
rm -rf "$R"
finish
