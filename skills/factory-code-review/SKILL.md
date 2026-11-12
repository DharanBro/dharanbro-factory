---
name: factory-code-review
description: Factory worker. Independent review of ONE repo's diff against the locked plan; auto-fix must-fix findings (max 2 rounds), list the rest as follow-ups. Launched by the factory lead.
---

Your cwd is the repo worktree `$TASK_DIR/$REPO`. You see ONLY: the diff (`git diff -w origin/<base>...HEAD`; for a file that is mostly reformatting, diff both sides through the repo's formatter instead, base from `$ROOT/repos.yml`), the plan's `## Acceptance criteria` + `## Repo: $REPO`, `decisions.md`, and for UI diffs the checklist below. Do not read the execute worker's logs or reasoning.

State lifecycle: for each new piece of state or store, list how it is created, updated and reset on record swap, re-render with equal data, unmount, hidden/disabled/skipped field, list row add/remove, and async completion after any of these. A missing path is must-fix.

Classify every finding:
- **must-fix**: bug, security issue, data loss, broken/missing acceptance criterion, plan not followed, missing test for new behaviour, time-sensitive or timeout-bound unit test (real timers/sleeps, long event loops), failing lint/typecheck/tests
- **should-fix**: maintainability, naming, duplication of an existing helper
- **nit**: style

If the diff changes UI code (components, markup, styles), also check its changed lines against `$ROOT/skills/factory-code-review/ui-checklist.md`, using the classes above. A rule broken in a way a user hits (keyboard or screen-reader access, focus, form labels and errors, empty/loading/error states, destructive action with no confirm or undo) is must-fix; any other rule is a nit. Skip rules the repo's design system already handles. Prefix these findings `[wig]` in the report.

Loop up to `caps.review_rounds` (2): fix all must-fix (commit `fix(<ID>): review: ...`), rerun the repo's test/lint/typecheck, re-review the new diff only. Never fix should-fix/nit and never loop on them.

Write `$TASK_DIR/artifacts/review-$REPO.md` (max ~40 lines): rounds, what was fixed, then `## Known follow-ups` (should-fix + nits, `path:line: issue`) and any unresolved must-fix.

Finish: `bash $ROOT/scripts/worker-done.sh $TASK $KEY <status> "<n fixed, m follow-ups>" '{"changed":<true|false>}'` where `changed` = you committed any fix; status `done`, or `blocked` if a must-fix remains after the last round.
