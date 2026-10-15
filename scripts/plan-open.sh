#!/usr/bin/env bash
# plan-open.sh <task>   count unresolved "- [ ]" items under "## Open questions" in plan.md (0 = grill done)
. "$(dirname "$0")/lib.sh"
f="$ROOT/tasks/${1:?task}/plan.md"
awk '/^## /{s=($0 ~ /^## Open questions/)} s && /^- \[ \]/{n++} END{print n+0}' "$f"
