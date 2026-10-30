---
name: factory
description: Run the end-to-end dev pipeline for a Jira key or a plain-text idea (research, plan, review, grill, execute, UI test, code review, draft PRs). Pass the task or idea and optional `--from <stage>`. Also the lead's playbook when the prompt says LEAD mode.
---

`ROOT` = this repo's root (two levels above this file). Run scripts as `bash $ROOT/scripts/<x>.sh`.

## Mode A: launcher (you were invoked by the user, prompt has no "LEAD mode")
1. Task id: arg matches `^[A-Z][A-Z0-9]+-[0-9]+$` -> that key (`kind=jira`). Existing `tasks/<arg>` -> resume it. Otherwise an idea: `idea-<3-5 word kebab slug>`.
2. `task-init.sh <id>`. Idea: write the user's raw text to `tasks/<id>/input.md`. Jira: write `Jira: <KEY>` to it. If `--from <stage>`: `state.sh <id> reset <stage>`.
3. `launch-lead.sh <id>`:
   - `LAUNCHED`/`FOCUSED`: reply in ONE line ("<id> lead starting in this workspace (renamed <id>); this session exits when the turn ends, grill will notify you") and stop. Do not run more tools after it.
   - `INLINE`: you are the lead: continue with Mode B in this session.

## Mode B: LEAD
Stay tiny. Read ONLY `state.json` (`state.sh <id> get`) and one-line worker results. Never open research/plan/review files except the 2 small reads named below. Workers do the thinking.

Loop: `s=$(state.sh $T next)`; run the stage below; on success `state.sh $T set <s> done`; on `no status file` or `agent start failed` re-run that worker once (next `TRY`); on any other failure, or the same one twice, STOP and tell the user the failing line + `tasks/$T/blocked.md` if present. A stage worker = `run-stage.sh $T <skill> <stage> [repo]` (prints one line, exit 0 = done; `LABEL=<name>` sets its key, `TRY=<n>` adds `-t<n>`). Mark `running` before each stage. When `next` prints `waves`, run `## Wave loop` until `state.sh $T wave-next` prints `complete`.

| stage | what the lead does |
|---|---|
| intake | `run-stage.sh $T factory-intake intake` |
| research | `sync-repos.sh`. Shortlist repos: `repos-brief.sh` output vs the title/summary of `input.md`. Err toward inclusion. No repos registered -> tell user to run `/factory-add-repo`. `state.sh $T update '.repos=[...]'`. Then `run-stages.sh $T factory-research research <repos...>` |
| plan | `run-stage.sh $T factory-plan plan`; then `plan-meta.sh $T` -> `state.sh $T update '.repos=<repos>'`; set `.branch` from `factory.yml git.branch` (`{id}`,`{slug}` = kebab title of `input.md`, <=5 words; ideas use `idea_branch`), unless `.branch` is already set (task continuing existing PRs: keep it). Then research what the plan added: every plan repo with no `research/<repo>.md` and a clone in `repos/` (unregistered existing repo: register it first, see `factory-add-repo` auto mode; repos the run creates are skipped) -> `run-stages.sh $T factory-research research "<those repos>"`, then re-run the plan once (`TRY=2 run-stage.sh $T factory-plan plan`) and redo the `plan-meta.sh` steps above. Never loop more than that once |
| plan_review | `run-stage.sh $T factory-plan-review plan_review` |
| grill | `run-stage.sh $T factory-grill grill` (human-interactive, so run it detached per `## Waiting`; exit 3 = no Herdr -> do the grill yourself following `skills/factory-grill/SKILL.md`; exit 4 = past the cap but the user is still in the grill tab: not a failure, never re-launch it, tell the user in one line and wait for `work/grill.json` with `pr-watch.sh --file`). Then require `plan-open.sh $T` == 0 and `plan-meta.sh` locked=true. Then re-run `plan-meta.sh $T` (plan_review/grill may change repos, waves, frontend) and `state.sh $T update '.repos=<repos>'`. Worktrees are created per wave (`## Wave loop`), because repos the run creates do not exist yet |

## Wave loop
`state.sh $T wave-next` prints `<wave> <step> <repos...>` or `complete`. It derives progress from `work/<step>-<repo>.json` (a done `-t<n>` try counts), so never record wave progress yourself: run the step for the repos it lists, then ask `wave-next` again. Pass the repo list as one quoted string; `run-stages.sh` splits it. Each wave runs every step before the next wave starts, so a wave that depends on an earlier one sees its PRs (draft mode) or its merged code (merge mode).

Before a wave's `execute` step, prepare each listed repo: no clone at `repos/<repo>` -> take its `plan-meta.sh $T`.remotes entry (none: STOP, the plan is missing `remote:`), wait for it with a detached `pr-watch.sh --repo <owner/name>`, then register it by following `skills/factory-add-repo/SKILL.md` in auto mode (`<owner/name> auto`: everything inferred, no questions). Then `new-worktree.sh $T <repo> <branch>` for every listed repo (idempotent; includes harness-only repos).

| step | what the lead does |
|---|---|
| execute | `run-stages.sh $T factory-execute execute "<repos>"`. Cross-repo dependencies on unreleased packages never block: workers use local tarballs (see factory-execute) |
| ui_test | The listed repos are this wave's `frontend` repos with `ui` not false (a library change is UI-tested through its consumer harness repo, in whichever wave the plan puts that repo). `run-stages.sh $T factory-ui-test ui_test "<repos>"`. Per failed repo (status `failed`): fix loop, up to `caps.fix_tries`: `EXTRA="mode=fix report=artifacts/test-report-<repo>.md" TRY=<n> run-stage.sh $T factory-execute fix <repo>` then `TRY=<n> run-stage.sh $T factory-ui-test ui_test <repo>`. Still failing -> write `tasks/$T/blocked.md` (repo, tries, last report path) and STOP. If summary contains `AUTH_EXPIRED`: tell user, run `ui-login.sh <dev_url>` (visible window), wait for "done", rerun that repo. |
| code_review | `run-stages.sh $T factory-code-review code_review "<repos>"`. For each frontend repo whose `work/code_review-<repo>.json` has `"changed":true`: rerun its ui_test once (same fix loop, next `TRY`) |
| ci_check | `run-stages.sh $T factory-ci-check ci_check "<repos>"`. Any `blocked` -> STOP (see `blocked.md`); the wave's PRs never open until every repo in it is green. The worker also writes `artifacts/approvals-<repo>.md` (`repo-rules.sh`: who must approve, from protection, CODEOWNERS and AUTO_APPROVERS) and runs the local Sonar scan (`scripts/sonar-scan.sh`) for repos with a `sonar:` block; issues on lines the branch changed block like any check (the server's whole-project gate is info only). Unverified checks (e.g. Sonar server down) do not block; they are listed in the PR. Neither do PRE-EXISTING ones: `ci-run.sh` re-runs a failing check on `origin/<base>`, and one that fails the same way there is not the branch's (`artifacts/ci-preexisting-<repo>.json`) |
| pr | `LABEL=pr-w<wave> EXTRA="repos=<a,b>" run-stage.sh $T factory-pr pr` (one worker for the wave's repos; draft or ready per `pr_mode`, Jira comment). Print the wave's rows of `artifacts/prs.md` |
| merge | Only listed in `pr_mode: merge`. Repos with `coderabbit` true in `prs.md`: run the `factory-review` loop on their PRs first (they open ready, so CodeRabbit reviews them). Then start a detached `pr-watch.sh <owner/repo#n>...` for the wave's PRs (`## Waiting`) and act on each line: `checks=FAILING(<names>)` -> save the failure (`circleci-failures.sh` or `gh run view <id> --log-failed`) to `artifacts/ci-fail-<repo>-t<n>.md` and run `EXTRA="mode=fix report=artifacts/ci-fail-<repo>-t<n>.md" TRY=<n> run-stage.sh $T factory-execute fix <repo>`, up to `caps.fix_tries`; `review=APPROVED checks=GREEN` -> merge per `## Merging`; approval missing -> tell the user who must give it (from `approvals-<repo>.md` and decisions.md) and keep watching. `ALL MERGED/CLOSED`: any PR closed unmerged -> STOP and tell the user; else `worker-done.sh $T merge-w<wave> done "<n> merged"` |

Done (`complete`): notify the user. Draft mode, next steps for them: review the draft PRs, mark ready, run `/factory-review <id>` (CodeRabbit loop; CodeRabbit skips drafts). Merge mode: list what merged.

## Lead autonomy
Decide yourself, no question, when the playbook, the locked plan or decisions.md already answers it:
- next stage/wave, opening PRs for a finished wave, re-running a worker once after `no status file` / `agent start failed`;
- marking a check UNVERIFIED when ci-run proved it fails identically on the base branch;
- merging a PR in `pr_mode: merge` once it is approved and every required check is green (`## Merging`);
- registering a repo the run created (factory-add-repo auto mode, inferred values);
- waiting: always a background watcher (`## Waiting`), never "tell me when".

Beyond that, decide yourself when highly confident; log each decision with its rationale under `## Lead decisions` in `tasks/<id>/decisions.md` (`- <date>: <decision>. Why: <rationale>.`) and tell the user in one line. Ask (one question, A/B/C, your pick marked) only for: low confidence, product or scope changes, anything that contradicts decisions.md, irreversible prod actions the plan does not list, approvals someone else must give (say who), and cap hits (fix_tries, review rounds, watcher timeout). This narrows the user's "always ask" reply rule for the factory lead only. Hard user rules (e.g. ask before creating Jira tickets) still win.

## Merging (`pr_mode: merge` only)
`plan-meta.sh $T`.pr_mode is `draft` unless the grill set `merge` (logged in decisions.md). In draft mode you never merge. In merge mode you merge a PR (`gh pr merge <n> --repo <o/r>` in the repo's usual style, e.g. `--squash`) only when both hold:
- GitHub allows it: approved per branch protection, every required check green (`pr-watch.sh` says `review=APPROVED checks=GREEN`), mergeable;
- the plan's approver for that repo (decisions.md) has approved, and anyone in `artifacts/approvals-<repo>.md` "Needs approval from" has too.
Never approve your own PR or ask a bot to; if an approval is missing, tell the user who must give it.

## Waiting (PRs, CI, repos, publishes, long stages)
Every wait goes through `scripts/pr-watch.sh`; never `sleep`, never ask the user to tell you when something happened.
- PRs and their CI: `pr-watch.sh <owner/repo#n>...`. A new repo: `--repo <owner/name>`. A package publish: `--npm <pkg@ver>...` (run it from the repo dir so its `.npmrc` picks the registry). A worker file: `--file <path>`. One line per state change; exit 0 when done, 3 at the 2 h cap (a cap hit is reported to the user).
- Anything that can outlive a few minutes runs detached, and Monitor only tails its log, because Monitor dies at 30 min: `nohup bash $ROOT/scripts/pr-watch.sh a/b#1 c/d#2 >> $ROOT/tasks/$T/work/watch-<label>.log 2>&1 &`, then Monitor `tail -n +1 -f <that log>`. The same goes for long `run-stage.sh`/`run-stages.sh` calls (the foreground Bash cap is 10 min).
- Load Monitor's schema first: ToolSearch `select:Monitor`.
- Your Bash and Monitor commands run in **zsh**, not bash: an unquoted `$var` is not split into words, and `declare -A` does not exist. Write PR refs and repo names out as separate literal arguments, and put any loop logic inside a `bash` script, never inline.

## After the user says an upstream PR is merged (package repo with changesets)
Standing authorization from the user (DP-7626): when they say a PR in a published package repo (e.g. encore-ui-toolkit) is merged, run this without asking again. It covers approving and squash-merging that repo's bot release PR only, never feature PRs.
1. Find the release PR: `gh pr list --repo <org/repo> --state open --head changeset-release/master` (title `<KEY>: release packages`, author `app/github-actions`). Not there yet -> wait per `## Waiting` until it appears (the "Create Release Pull Request or Publish" run on master creates it).
2. Check before approving: not draft, `mergeable`, all checks green. Read the new versions from its diff (`gh pr diff`), not from the plan: peer-dependency cascades turn a `minor` changeset into a major bump for dependents (DP-7626: toolkit 24.4.0 -> 25.0.0, entity-detail 28.1.0 -> 29.0.0). Tell the user the final versions; a red check or a surprise beyond that cascade -> STOP and ask.
3. `gh pr review <n> --approve --body "<what it releases>, approved on behalf of the owner at their request"`, then `gh pr merge <n> --squash`. Repos with a different merge style: copy the style of earlier release commits on master.
4. Wait for the publish: from the repo dir, detached `pr-watch.sh --npm @<scope>/<pkg>@<ver> ...` (registry comes from the repo `.npmrc`, usually GitHub Packages), Monitor tailing its log. On the cap, report and ask.
5. Unblock the dependent PRs (those red on `Install Dependencies`/`catalog-check` for the unpublished version): per repo in its worktree, merge the base, set the dependency ranges to the published versions, regenerate the lockfile against the registry (no `file:` refs, overrides or tarball lockfile), run the repo gates, push via a `factory-execute` fix worker, then watch CI with `pr-watch.sh`. Code changes also need the UI check first (`factory-ui-test`); a lockfile-only change does not. Then refresh the PR descriptions that mention "unreleased"/"blocked on".
6. Report in 2-3 lines: versions released, which PRs are green, what still needs the user (approval/merge of the dependent PRs; you never merge those).

Resume by following this playbook with the same task id: `state.sh next` picks up the first unfinished stage, then `wave-next` the first unfinished wave step; finished work never reruns. Execute resumes per slice from `work/progress-<repo>.txt`.
