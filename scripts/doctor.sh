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

# Claude plugin the workers rely on (README Setup step 4).
if command -v claude >/dev/null 2>&1; then
  if claude plugin list --json 2>/dev/null | jq -e 'any(.[]; .enabled and .id == "ponytail@ponytail")' >/dev/null; then
    chk "plugin ponytail" ok; else chk "plugin ponytail" "MISSING (README Setup step 4)"; fail=1; fi
fi

# Every "Factory worker" skill needs a stage in factory.yml (model, effort): factory-<a-b> -> stage a_b.
if command -v ruby >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  stages=$(conf | jq -r '.stages | keys[]'); missing=""
  for f in "$ROOT"/skills/*/SKILL.md; do
    grep -q '^description: Factory worker' "$f" || continue
    s=$(basename "$(dirname "$f")"); s=${s#factory-}; s=${s//-/_}
    grep -qx "$s" <<<"$stages" || missing="$missing $s"
  done
  if [ -z "$missing" ]; then chk "worker stages" ok; else chk "worker stages" "MISSING in factory.yml:$missing"; fail=1; fi
fi

if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then chk "gh auth" ok; else chk "gh auth" "MISSING (gh auth login)"; fail=1; fi
fi

if [ -f "$ROOT/secrets.env" ]; then bash "$ROOT/scripts/secrets-check.sh"; else chk secrets.env "missing (cp secrets.env.example secrets.env)"; fi

exit "$fail"
