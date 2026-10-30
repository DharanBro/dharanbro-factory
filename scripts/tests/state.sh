#!/usr/bin/env bash
# state.sh: next stops at "waves"; wave-next walks every step of every wave from work files (tries count, a
# look-alike repo name does not); reset archives wave work files.
. "$(dirname "$0")/lib.sh"
R=$(fake_root state.sh plan-meta.sh task-init.sh worker-done.sh)
s() { FACTORY_ROOT="$R" bash "$R/scripts/state.sh" t "$@"; }
wd() { FACTORY_ROOT="$R" bash "$R/scripts/worker-done.sh" t "$1" "${2:-done}" x; }
FACTORY_ROOT="$R" bash "$R/scripts/task-init.sh" t >/dev/null
cat > "$R/tasks/t/plan.md" <<'EOF'
---
pr_mode: merge
repos:
  - {name: a, wave: 1, type: frontend}
  - {name: b, wave: 1, type: backend}
  - {name: c, wave: 2, type: backend}
---
EOF
ok next-intake "$(s next)" intake
for st in intake research plan plan_review grill; do s set "$st" "done"; done
ok next-waves "$(s next)" waves
ok w1-execute "$(s wave-next)" "1 execute a b"
wd execute-a; wd execute-b failed; wd execute-b-tools
ok failed-is-not-done "$(s wave-next)" "1 execute b"
wd execute-b-t2
ok try-counts "$(s wave-next)" "1 ui_test a"
wd ui_test-a; wd code_review-a; wd code_review-b; wd ci_check-a; wd ci_check-b
ok w1-pr "$(s wave-next)" "1 pr a b"
wd pr-w1
ok w1-merge "$(s wave-next)" "1 merge a b"
wd merge-w1
ok w2-execute "$(s wave-next)" "2 execute c"
s reset ui_test
ok reset-step "$(s wave-next)" "1 ui_test a"
ok reset-kept-execute "$(find "$R/tasks/t/work" -maxdepth 1 -name 'execute-*.json' | wc -l | tr -d ' ')" 4
s reset grill
ok reset-stage "$(s next) $(find "$R/tasks/t/work" -maxdepth 1 -name '*.json' | wc -l | tr -d ' ')" "grill 0"
rm -rf "$R"
finish
