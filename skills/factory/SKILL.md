---
name: factory
description: Run the end-to-end dev pipeline for a Jira key or a plain-text idea (research, plan, review, grill, execute, UI test, code review, draft PRs). Pass the task or idea and optional `--from <stage>`. Also the lead's playbook when the prompt says LEAD mode.
---

`ROOT` = this repo's root (two levels above this file). Run scripts as `bash $ROOT/scripts/<x>.sh`.

## Mode A: launcher (you were invoked by the user, prompt has no "LEAD mode")
1. Task id: arg matches `^[A-Z][A-Z0-9]+-[0-9]+$` -> that key (`kind=jira`). Existing `tasks/<arg>` -> resume it. Otherwise an idea: `idea-<3-5 word kebab slug>`.
2. `task-init.sh <id>`. Idea: write the user's raw text to `tasks/<id>/input.md`. Jira: write `Jira: <KEY>` to it. If `--from <stage>`: `state.sh <id> reset <stage>`.
3. `launch-lead.sh <id>`:
   - `LAUNCHED`/`FOCUSED`: reply in ONE line ("<id> running in Herdr workspace <id>, grill will notify you") and stop.
   - `INLINE`: you are the lead: continue with Mode B in this session.

## Mode B: LEAD
Stay tiny. Read ONLY `state.json` (`state.sh <id> get`) and one-line worker results. Never open research/plan/review files except the 2 small reads named below. Workers do the thinking.

Loop: `s=$(state.sh $T next)`; run the stage below; on success `state.sh $T set <s> done`; on failure STOP, tell the user the failing line + `tasks/$T/blocked.md` if present. A stage worker = `run-stage.sh $T <skill> <stage> [repo]` (prints one line, exit 0 = done). Mark `running` before each stage.

| stage | what the lead does |
|---|---|
| intake | `run-stage.sh $T factory-intake intake` |
| research | `sync-repos.sh`. Shortlist repos: `repos-brief.sh` output vs the title/summary of `input.md`. Err toward inclusion. No repos registered -> tell user to run `/factory-add-repo`. `state.sh $T update '.repos=[...]'`. Then `run-stages.sh $T factory-research research <repos...>` |
| plan | `run-stage.sh $T factory-plan plan`; then `plan-meta.sh $T` -> `state.sh $T update '.repos=<repos>'`; set `.branch` from `factory.yml git.branch` (`{id}`,`{slug}` = kebab title of `input.md`, <=5 words; ideas use `idea_branch`), unless `.branch` is already set (task continuing existing PRs: keep it) |
| plan_review | `run-stage.sh $T factory-plan-review plan_review` |
| grill | `run-stage.sh $T factory-grill grill` (human-interactive; exit 3 = no Herdr -> do the grill yourself following `skills/factory-grill/SKILL.md`). Then require `plan-open.sh $T` == 0 and `plan-meta.sh` locked=true. Then re-run `plan-meta.sh $T` (plan_review/grill may change repos, waves, frontend) and `state.sh $T update '.repos=<repos>'`. Then `new-worktree.sh $T <repo> <branch>` for each plan repo, including harness-only repos |
| execute | for each wave in `plan-meta.sh $T`.waves (ascending): `run-stages.sh $T factory-execute execute <repos in wave>`; wait for the whole wave before the next. Cross-repo dependencies on unreleased packages never block: workers use local tarballs (see factory-execute) |
| ui_test | `frontend` repos with `ui` not false (see `plan-meta.sh`; none -> mark done; never skip on a stale plan-meta: re-read it now; a library change must be UI-tested through its consumer harness repo). `run-stages.sh $T factory-ui-test ui_test <fe repos>`. Per failed repo (status `failed`): fix loop, up to `caps.fix_tries`: `EXTRA="mode=fix report=artifacts/test-report-<repo>.md" TRY=<n> run-stage.sh $T factory-execute fix <repo>` then `TRY=<n> run-stage.sh $T factory-ui-test ui_test <repo>`. Still failing -> write `tasks/$T/blocked.md` (repo, tries, last report path) and STOP. If summary contains `AUTH_EXPIRED`: tell user, run `ui-login.sh <dev_url>` (visible window), wait for "done", rerun that repo. |
| code_review | `run-stages.sh $T factory-code-review code_review <all repos>`. For each frontend repo whose `work/code_review-<repo>.json` has `"changed":true`: rerun its ui_test once (same fix loop) |
| ci_check | `run-stages.sh $T factory-ci-check ci_check <all repos>`. Any `blocked` -> STOP (see `blocked.md`); the PR stage never runs until every repo is green. The worker also runs the local Sonar scan (`scripts/sonar-scan.sh`) for repos with a `sonar:` block; issues on lines the branch changed block like any check (the server's whole-project gate is info only). Unverified checks (e.g. Sonar server down) do not block; they are listed in the PR |
| pr | `run-stage.sh $T factory-pr pr` (single worker: all repos, cross-linked draft PRs, Jira comment). Then print the table from `artifacts/prs.md` and the path `artifacts/testing-evidence.html` |

Done: notify user. Next steps for them: review the draft PRs, mark ready, run `/factory-review <id>` (CodeRabbit loop; CodeRabbit skips drafts).

Resume by following this playbook with the same task id: `state.sh next` picks up the first unfinished stage; finished stages never rerun. Execute resumes per slice from `work/progress-<repo>.txt`.
