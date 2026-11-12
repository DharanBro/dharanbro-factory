---
name: factory-review
description: CodeRabbit loop for a factory task's PRs. Run after you mark the draft PRs "ready for review" (CodeRabbit skips drafts). Pass the task id.
---

`ROOT` = repo root. Inputs: `tasks/<id>/artifacts/prs.md`, `factory.yml` (`caps.coderabbit_rounds`). Keep chat minimal: you only handle counts and one-line worker results.

1. For each PR row with `coderabbit=true`: `gh pr view <url> --json isDraft -q .isDraft`. If draft -> tell the user "mark ready first" and skip that repo. No eligible repos -> stop.
2. Per eligible repo, in parallel, round r = 1..`coderabbit_rounds`:
   - `n=$(bash $ROOT/scripts/cr-fetch.sh <id> <repo> <pr#> <r>)` (blocks until CodeRabbit has reviewed the latest commit; prints unresolved-thread count; `TIMEOUT` -> report and stop that repo).
   - `n == 0` -> repo is clean, stop its loop.
   - else `EXTRA="mode=coderabbit comments=artifacts/coderabbit-<repo>-r<r>.md pr=<pr#>" TRY=<r> bash $ROOT/scripts/run-stage.sh <id> factory-execute fix <repo>` (worker fixes or replies with `@coderabbitai` and pushes; a valid finding is always fixed in this PR, never deferred as "follow-up" or "out of scope" unless decisions.md has the user's OK for that thread). Then next round. Run the UI test (`ui_test` for the repo's harness app) only when the fix touched renderer, component or other UI files, in parallel with the next `cr-fetch.sh` call; no fixed sleep before `cr-fetch.sh` (it already waits on the head sha).
3. Round limit hit with comments still open -> STOP, give the user a per-repo summary (open comment count + file paths from the `artifacts/coderabbit-*` files) and let them decide.
4. All repos clean -> tell the user the PRs are ready to merge-review. Do not merge or approve anything.
