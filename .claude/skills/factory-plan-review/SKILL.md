---
name: factory-plan-review
description: Factory worker. Fresh-eyes review of plan.md against the code; fix factual errors, queue human-only questions. Launched by the factory lead.
---

Inputs: `$TASK_DIR/plan.md`, `$TASK_DIR/input.md`, `$TASK_DIR/research/*.md`. Code in `$ROOT/repos/<repo>` (read-only) to verify claims.

Check, spot-reading code rather than trusting the plan:
- every file/function/path the plan names exists and behaves as claimed
- requirements in input.md all covered by acceptance criteria; criteria are testable
- slices are vertical, ordered, each leaves tests green; waves/dependencies correct
- missed consumers of changed APIs, missed edge cases, contradictions with repo conventions
- frontend repos: ui_test_doc present, UI scenarios concrete

Actions:
1. Factual errors: fix directly in `plan.md` (minimal edits).
2. Anything only a human can decide, or that you cannot settle from code: append to `## Open questions` as `- [ ] <q> -- recommended: <default>`.
3. Write `$TASK_DIR/plan-review.md`, max ~40 lines: findings as `severity | what | fixed or queued`.

Finish: `bash $ROOT/scripts/worker-done.sh $TASK $KEY done "<n fixed, m questions queued>"`.
