#!/usr/bin/env bash
# doctor.sh   Check factory prerequisites (README "Setup"). One line per check; exit 1 if anything required is missing.
. "$(dirname "$0")/lib.sh"
fail=0
chk() { printf '%-22s %s\n' "$1" "$2"; }
need() { if command -v "$1" >/dev/null 2>&1; then chk "$1" ok; else chk "$1" MISSING; fail=1; fi; }

for t in git gh jq ruby curl python3 node headroom; do need "$t"; done
if command -v herdr >/dev/null 2>&1; then chk herdr ok; else chk herdr "missing (recommended: curl -fsSL https://herdr.dev/install.sh | sh; workers run headless)"; fi

# Agent CLIs the configured stages launch (agent_override wins over per-stage defaults).
if command -v ruby >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  for c in $(conf | jq -r '(if .agent_override then [.agent_override] else [.stages[].default] | unique end)[] as $a | .agents[$a].headless.command[0]'); do need "$c"; done
fi

# Claude plugins the skills rely on (README Setup step 4).
if command -v claude >/dev/null 2>&1; then
  on=$(claude plugin list --json 2>/dev/null | jq -r '.[] | select(.enabled) | .id' || true)
  for p in playwright@claude-plugins-official ponytail@ponytail caveman@caveman; do
    if grep -qx "$p" <<<"$on"; then chk "plugin ${p%%@*}" ok; else chk "plugin ${p%%@*}" "MISSING (README Setup step 4)"; fail=1; fi
  done
fi

if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then chk "gh auth" ok; else chk "gh auth" "MISSING (gh auth login)"; fail=1; fi
fi

if [ -f "$ROOT/secrets.env" ]; then bash "$ROOT/scripts/secrets-check.sh"; else chk secrets.env "missing (cp secrets.env.example secrets.env)"; fi

exit "$fail"
