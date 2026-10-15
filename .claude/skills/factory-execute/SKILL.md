---
name: factory-execute
description: Factory worker. Implement ONE repo's slices from the locked plan with TDD in its worktree; also handles fix mode (failing UI test report) and coderabbit mode (review comments). Launched by the factory lead.
---

Your cwd is the repo worktree `$TASK_DIR/$REPO` (its CLAUDE.md applies). Touch only this repo. Never push (the PR stage does). Never edit plan.md.

Inputs: from `$TASK_DIR/plan.md` read ONLY `## Goal`, `## Acceptance criteria`, and `## Repo: $REPO`; `$TASK_DIR/decisions.md`; this repo's entry in `$ROOT/repos.yml` (install/test/lint/typecheck). `$TASK_DIR/state.json` has the branch.

## mode normal (default)
1. Install deps if missing (`install` command).
2. Resume point: slice numbers already in `$TASK_DIR/work/progress-$REPO.txt` are done; continue with the next. 
3. Per slice: write the failing test, see it fail, implement, see it pass, run lint + typecheck + the affected tests, then commit: `<type>(<ID>): <subject>` (Conventional Commits; ID = Jira key or idea slug from state.json) with trailer `Co-Authored-By: Claude <noreply@anthropic.com>`. Then append `slice N <sha>` to the progress file.
4. Same failure 3 times in a row (`caps.fix_tries`) -> write `$TASK_DIR/blocked.md` (what, tries, output tail), finish `blocked`.
5. Unit tests must not be time-sensitive: no real clocks/timers, no sleeps, no tight timeouts, and no long loops of UI events (CI is slower than local; a 5s default timeout flaked in DP-6969). Use fake timers or deterministic waits, and keep each test small and fast. Never fix flakiness by raising a timeout.
6. At the end run the full test + lint + typecheck once. Reuse existing helpers; add nothing the plan does not ask for.

## mode fix (`EXTRA` has `mode=fix report=<path>`)
Read only that report (relative to `$TASK_DIR`). Fix the root cause of each failure with a regression test where feasible, commit `fix(<ID>): ...`. Do not widen scope.

## mode coderabbit (`EXTRA` has `mode=coderabbit comments=<path> pr=<n>`)
For each comment in the file: if valid, fix it (commit `fix(<ID>): address review ...`). If already handled by existing code or you disagree with reason, reply on the thread instead: `gh api repos/<owner>/<repo>/pulls/<pr>/comments/<comment id>/replies -f body="@coderabbitai <where/how it is handled>"`. Push once at the end: `git push`.

Finish: `bash $ROOT/scripts/worker-done.sh $TASK $KEY done "<n slices | n fixes>, tests green"`.
