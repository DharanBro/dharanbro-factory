---
name: factory-pr
description: Factory worker. Push each touched repo's branch, open cross-linked DRAFT PRs, write artifacts/prs.md, comment on the Jira ticket. Launched by the factory lead (single worker for all repos).
---

Precondition: every `artifacts/ci-check-<repo>.md` exists and has no FAIL; otherwise finish `blocked` and open nothing.

Inputs: `$TASK_DIR/state.json` (repos, branch, kind), `$TASK_DIR/plan.md` (`## Goal`, acceptance criteria), `$TASK_DIR/artifacts/test-report-*.md` and `review-*.md`, `$TASK_DIR/input.md` title, `$ROOT/repos.yml` (base branch, coderabbit flag). Worktrees: `$TASK_DIR/<repo>`.

For each repo (work from its worktree):
1. `git push -u origin <branch>` (never force, never the base branch).
2. `gh pr create --draft --base <base> --title "<type>(<ID>): <title>" --body-file <tmp>` with a body of: **Summary** (2-3 lines), **Changes** (bullets), **Testing** (unit + UI + local CI-check results from the reports, 1 line each, plus the `## Unverified locally` list from `ci-check-<repo>.md`), **Known follow-ups** (copied from the review file), **Related PRs** (filled in step 3), and last line `🤖 Generated with [Claude Code](https://claude.com/claude-code)`. Before creating PRs run `bash $ROOT/scripts/evidence-html.sh $TASK`: it builds `artifacts/testing-evidence.html` (UI test reports with inlined screenshots, CI checks, code review). Mention that path in **Testing**; never upload it.
   **Existing PR:** if `gh pr list --head <branch> --state open --json number,url,isDraft` returns one, do not create a PR. Push (step 1), then rewrite its body with `gh pr edit --body-file` so every claim matches the branch as it is now: keep the existing structure and sections, update or remove anything the new commits changed, add the Testing and Unverified items above; no appended changelog. Never change its draft/ready state.
3. When all PRs exist, `gh pr edit` each body to list the sibling PR URLs.
4. Write `$TASK_DIR/artifacts/prs.md`: table `repo | PR url | number | branch | base | coderabbit(true/false)`.
5. Jira task and `jira.comment_on_pr` true: ONE comment on the issue with the PR links (Atlassian MCP `addCommentToJiraIssue`). No status transitions, no other edits.

Finish: `bash $ROOT/scripts/worker-done.sh $TASK $KEY done "<n> draft PRs: <urls>"`.

Atlassian tools: if `mcp__atlassian__*` returns 403 "app is not installed", use the `mcp__claude_ai_Atlassian__*` equivalents (same names, load via ToolSearch).
