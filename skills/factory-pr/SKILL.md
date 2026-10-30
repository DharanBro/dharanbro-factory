---
name: factory-pr
description: Factory worker. Push each touched repo's branch, open cross-linked PRs (draft unless the plan sets pr_mode merge), write artifacts/prs.md, comment on the Jira ticket. Launched by the factory lead (one worker per wave).
---

Scope: the repos in `repos=<a,b>` from EXTRA (the lead passes one wave); no `repos=` -> every repo in `state.json`. PR mode: `bash $ROOT/scripts/plan-meta.sh $TASK | jq -r .pr_mode` (`draft` or `merge`).

Precondition: for every repo in scope, `artifacts/ci-check-<repo>.md` exists and none of its checks is FAIL; otherwise finish `blocked` and open nothing. PRE-EXISTING checks (`artifacts/ci-preexisting-<repo>.json`: they fail the same way on the base branch) never block.

Inputs: `$TASK_DIR/state.json` (repos, branch, kind), `$TASK_DIR/plan.md` (`## Goal`, acceptance criteria), `$TASK_DIR/artifacts/test-report-*.md`, `review-*.md`, and `tarball-install-*.md`, `$TASK_DIR/input.md` title, `$ROOT/repos.yml` (base branch, coderabbit flag). Worktrees: `$TASK_DIR/<repo>`.

For each repo in scope (work from its worktree):
1. `git push -u origin <branch>` (never force, never the base branch).
2. `gh pr create [--draft] --base <base>` (`--draft` only when pr_mode is `draft`; in `merge` mode the PR opens ready for review)  with `--title "<type>(<ID>): <title>" --body-file <tmp>` and a body of: **Summary** (2-3 lines), **Changes** (bullets), **Testing** (unit + UI + local CI-check results from the reports, 1 line each, plus the `## Unverified locally` list from `ci-check-<repo>.md`, where each PRE-EXISTING check reads "fails on <base> too, not caused by this PR"), **Known follow-ups** (copied from the review file, plus one line per `## Unreleased deps` entry in `tarball-install-<repo>.md`: "release <pkg>@<ver>, then regenerate lockfile and push"), and **Related PRs** (filled in step 3). Before creating PRs run `bash $ROOT/scripts/evidence-html.sh $TASK`: it builds `artifacts/testing-evidence.html` (UI test reports with inlined screenshots, CI checks, code review). Mention that path in **Testing**; never upload it.
   **Existing PR:** if `gh pr list --head <branch> --state open --json number,url,isDraft` returns one, do not create a PR. Push (step 1), then rewrite its body with `gh pr edit --body-file` so every claim matches the branch as it is now: keep the existing structure and sections, update or remove anything the new commits changed, add the Testing and Unverified items above; no appended changelog. Never change its draft/ready state.
3. When all PRs in scope exist, `gh pr edit` each body to list the sibling PR URLs (this wave's plus any already in `prs.md` from earlier waves).
4. Update `$TASK_DIR/artifacts/prs.md`: table `repo | PR url | number | branch | base | coderabbit(true/false) | needs approval from` (last column: the first line of `artifacts/approvals-<repo>.md` after "Needs approval from:", or "unknown" if the file is missing). Add or replace the rows for the repos in scope; keep rows of other repos.
5. Jira task and `jira.comment_on_pr` true: ONE comment on the issue with this run's PR links using the configured Jira integration. No status transitions, no other edits.

Finish: `bash $ROOT/scripts/worker-done.sh $TASK $KEY done "<n> <draft|ready> PRs: <urls>"`. Never merge or approve a PR; merging belongs to the lead.

If the Jira integration is unavailable, record the missing access as blocked; do not invent ticket details.
