#!/usr/bin/env bash
# plan-meta.sh: pr_mode defaults to draft, passes merge through, rejects anything else.
. "$(dirname "$0")/lib.sh"
R=$(fake_root plan-meta.sh); mkdir -p "$R/tasks/t"
pm() { printf -- '---\n%brepos:\n  - {name: a, wave: 1, type: frontend}\n  - {name: b, wave: 2}\n---\n' "$1" > "$R/tasks/t/plan.md"
       FACTORY_ROOT="$R" bash "$R/scripts/plan-meta.sh" t 2>&1 | jq -c "$2" 2>/dev/null || echo error; }
ok default-draft "$(pm '' '[.pr_mode,.waves,.frontend]')" '["draft",[{"wave":1,"repos":["a"]},{"wave":2,"repos":["b"]}],["a"]]'
ok merge "$(pm 'pr_mode: merge\n' .pr_mode)" '"merge"'
ok invalid "$(pm 'pr_mode: yolo\n' .pr_mode)" 'error'
rm -rf "$R"
finish
