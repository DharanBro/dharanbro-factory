---
name: factory-execute
description: Factory worker. Implement ONE repo's slices from the locked plan with TDD in its worktree; also handles fix mode (failing UI test report) and coderabbit mode (review comments). Launched by the factory lead.
---

Your cwd is the repo worktree `$TASK_DIR/$REPO`; follow its local instructions. Touch only this repo (exception: building/packing a sibling worktree for step 2; leave it with no uncommitted changes, `git status` clean, afterwards). Never push before the PR exists (the PR stage opens it); once the branch has an open PR (`gh pr list --head <branch> --json number`), every run ends with a plain `git push`, never force. Never edit plan.md.

Inputs: from `$TASK_DIR/plan.md` read ONLY `## Goal`, `## Acceptance criteria`, and `## Repo: $REPO`; `$TASK_DIR/decisions.md`; this repo's entry in `$ROOT/repos.yml` (install/test/lint/typecheck). `$TASK_DIR/state.json` has the branch.

All modes:
- Build the least that meets the plan and acceptance criteria. Reuse existing code/stdlib/installed deps before writing new; no speculative abstractions, config, or files. Never drop plan slices, TDD, validation, error handling, or tests to be lazy.
- Unit tests must not be time-sensitive: no real clocks/timers, no sleeps, no tight timeouts, no long loops of UI events (CI is slower than local; a 5s default timeout flaked in DP-6969). Use fake timers or deterministic waits and keep each test small and fast. Never fix flakiness by raising a timeout.
- UI slices (a slice adds or changes something people see, in an app or a component library): before the first one, read `$ROOT/skills/factory-execute/ui-craft.md` and apply it. Add no new tokens, palettes or fonts, and restyle nothing beyond the plan. The browser check is the ui_test stage's job.
- Before each commit run `git diff --cached --stat`: unstage generated files (compiled .js/.d.ts next to sources, dist, coverage) and any file the fix did not mean to touch.
- After any install (step 1 on resume, fix mode, coderabbit mode), re-apply `$TASK_DIR/artifacts/tarball-install-$REPO.md` if present; a plain install fails once an unreleased bump is committed.

## mode normal (default)
1. Install deps if missing (`install` command).
2. Depends on a sibling repo's unreleased changes (same task, earlier wave, not yet published)? Never block on it. In the sibling worktree build and pack the changed packages into tarballs under `$TASK_DIR/artifacts/tarballs/$REPO/`, and install them in this repo locally (package-manager overrides or `file:` paths) to run gates. Commit only the real version bumps; never commit tarball/`file:` refs, overrides, or a tarball-resolved lockfile (revert them before committing). Write `$TASK_DIR/artifacts/tarball-install-$REPO.md`: the exact local-install steps (ui_test and ci_check reuse them), then `## Unreleased deps`, one line each `<package> | <sibling repo> | <version>` (ci_check and pr read it).
3. Resume point: slice numbers already in `$TASK_DIR/work/progress-$REPO.txt` are done; continue with the next. 
4. Per slice: write the failing test, see it fail, implement, see it pass, run lint + typecheck + the affected tests, then commit: `<type>(<ID>): <subject>` (Conventional Commits; ID = Jira key or idea slug from state.json). Then append `slice N <sha> red=<exit code of the first run of the new test, before the implementation>` to the progress file. If you did not see the test fail first, write `red=none`; never invent a code.
5. Same failure 3 times in a row (`caps.fix_tries`) -> write `$TASK_DIR/blocked.md` (what, tries, output tail), finish `blocked`.
6. At the end run the full test + lint + typecheck once.

## mode fix (`EXTRA` has `mode=fix report=<path>`)
Read only that report (relative to `$TASK_DIR`). Fix the root cause of each failure with a regression test where feasible, commit `fix(<ID>): ...`. Do not widen scope. If the branch already has an open PR (`gh pr list --head <branch> --json number`), push only after the CodeRabbit plugin review (when `bash $ROOT/scripts/cr-enabled.sh $REPO` prints `true`: procedure in `$ROOT/skills/factory-coderabbit-review/SKILL.md`, max 3 runs, writes `artifacts/cr-review-$REPO.md`) and `bash $ROOT/scripts/push-gate.sh $TASK $REPO` exit 0 (fix every finding it reports, commit, rerun; see Gate answers); then `git push` at the end (plain push, never force). `worker-done.sh` fails `done` without a gate record for the pushed sha.

## mode coderabbit (`EXTRA` has `mode=coderabbit comments=<path> pr=<n>`)
For each comment in the file: if valid, fix it (commit `fix(<ID>): address review ...`). If already handled by existing code, reply on the thread instead: `gh api repos/<owner>/<repo>/pulls/<pr>/comments/<comment id>/replies -f body="@coderabbitai <where/how it is handled>"`. For each valid finding, grep the repo for the same pattern and fix every site; end your summary with `sites checked: <file:line ...>`.
Reply on every thread in the same round, fixed or not, naming the commit (same `gh api` call, `@coderabbitai fixed in <sha>: <what>`). Push once at the end, only after the CodeRabbit plugin review (repos with `coderabbit: true`, see fix mode) and `bash $ROOT/scripts/push-gate.sh $TASK $REPO` exit 0 (fix every finding it reports, commit, rerun); then `git push`.
A valid finding is fixed in this PR. Reply without a fix only when existing code already handles it (say where). Never answer a valid finding with "follow-up" or "out of scope" unless decisions.md records the user's OK for that thread.

Gate answers: a valid push-gate or plugin-review finding is fixed, never answered away. Only when existing code already handles it, append `- <file> | <match key, 8+ chars from the finding's title/text> | <reason naming the file:line that handles it>` to `$TASK_DIR/artifacts/push-gate-answers-$REPO.md`; the plugin review record cites it and the gate accepts that answered finding (lead and PR body show it). Never answer with "follow-up" or "out of scope" unless decisions.md has the owner's OK for it.

Normal mode, before finishing: list slices whose `red=` is `none` or `0` in `$TASK_DIR/artifacts/tdd-flags.md` (one line each: slice, sha, subject). Flag only; do not redo them. For the retro. Skip the file if none.

Finish: `bash $ROOT/scripts/worker-done.sh $TASK $KEY done "<n slices | n fixes>, tests green[, n slices tdd-flagged]"`.
