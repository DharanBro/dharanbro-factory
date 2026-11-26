---
name: factory-coderabbit-review
description: Factory worker. Pre-push CodeRabbit review of ONE repo's branch through the CodeRabbit Claude Code plugin, only for repos with `coderabbit: true` in repos.yml. Also the review procedure every push path follows. Launched by the factory lead after code review.
---

Your cwd is the repo worktree `$TASK_DIR/$REPO`. Needs the Claude harness (the plugin does not exist in codex); on another harness finish `blocked` "coderabbit plugin needs claude".

Gate first: `bash $ROOT/scripts/cr-enabled.sh $REPO`. Not `true` -> finish `done` "skipped, coderabbit off for $REPO" and stop (the wave step and push-gate.sh skip such repos anyway).

## Review procedure (same for every push path)
1. Tree clean, `git fetch`, base merged in (merge, not rebase). The review covers committed changes only.
2. Review through the plugin: use the `coderabbit:code-reviewer` agent (Agent tool, `subagent_type: "coderabbit:code-reviewer"`) with the prompt "review committed changes in <worktree path> against origin/<base> (`--type committed --base origin/<base>`)". It needs the CodeRabbit CLI authenticated; if it reports not authenticated or a rate limit, finish `blocked` with that text and never push. Lean workers load the agent but not the `coderabbit:code-review` skill; the agent is enough.
3. Fix every valid finding at the root cause, commit `fix(<ID>): address coderabbit review ...`, run lint + typecheck + affected tests, then review again. At most 3 review runs per push. Not clean after the third -> write `$TASK_DIR/blocked.md` (open findings), do not push, finish `blocked`.
4. A finding is answered, not fixed, only when existing code already handles it: append `- <file> | <match key, 8+ chars from the finding> | <reason naming file:line>` to `$TASK_DIR/artifacts/push-gate-answers-$REPO.md`. Never "follow-up" or "out of scope" unless decisions.md has the owner's OK.
5. After the last commit or merge, write `$TASK_DIR/artifacts/cr-review-$REPO.md` (rewrite from scratch each time):
```
# coderabbit review: <repo>
head: <git rev-parse HEAD, full sha>
result: clean
runs: <n>
## findings
- <file> | <title> | fixed in <sha>
- <file> | <title> | answered <file:line>
```
A finding line that is neither `fixed in <sha>` nor `answered <file:line>`, or a HEAD that moved after the record, fails `push-gate.sh`. Never run a real review on a repo you were not told to.

Stage run: do the procedure, then `bash $ROOT/scripts/worker-done.sh $TASK $KEY done "<n runs, m findings fixed, k answered>" '{"changed":<true|false>}'` (`changed` = fix commits made).
