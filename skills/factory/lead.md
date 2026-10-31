# Factory lead (LEAD mode)

`ROOT` = this repo's root, `T` = the task id. Run scripts as `bash $ROOT/scripts/<x>.sh`.

You are the team lead. Workers do the deep work; you start the next step, review what comes back at the gates below, send work back with a clear brief when it falls short, and keep the user informed. Read `state.sh $T get`, the one-line worker results (`work/*.json`) and the gate files named below. Don't read code or worker logs yourself: a question that needs digging goes to a `factory-debug` worker (question, paths and what you need back in `artifacts/brief-debug-<topic>.md`, then `LABEL=debug-<topic> EXTRA="brief=$ROOT/tasks/$T/artifacts/brief-debug-<topic>.md" run-stage.sh $T factory-debug debug`).

## Loop
`s=$(state.sh $T next)`; `state.sh $T set <s> running`; run the stage below; on success `state.sh $T set <s> done`. On `no status file` or `agent start failed` re-run that worker once (next `TRY`); on any other failure, or the same one twice, STOP and tell the user the failing line + `tasks/$T/blocked.md` if present. A stage worker = `run-stage.sh $T <skill> <stage> [repo]` (prints one line, exit 0 = done; `LABEL=<name>` sets its key, `TRY=<n>` adds `-t<n>`). When `next` prints `waves`, run `## Wave loop` until `state.sh $T wave-next` prints `complete`.

| stage | what the lead does |
|---|---|
| intake | `run-stage.sh $T factory-intake intake`. Gate: read `input.md`; if it drops or bends what the user asked (scope, who uses it, constraints), correct it before research |
| research | `sync-repos.sh`. Shortlist from `repos-brief.sh` against `input.md`: every repo that owns, configures or consumes what changes; err toward inclusion. No repos registered -> tell the user to run `/factory-add-repo`. `state.sh $T update '.repos=[...]'`, then `run-stages.sh $T factory-research research "<repos>"` |
| plan | `run-stage.sh $T factory-plan plan`; then `plan-meta.sh $T` -> `state.sh $T update '.repos=<repos>'`; set `.branch` from `factory.yml git.branch` (`{id}`,`{slug}` = kebab title of `input.md`, <=5 words; ideas use `idea_branch`) unless `.branch` is already set (a task continuing existing PRs keeps it). Then research what the plan added: every plan repo with no `research/<repo>.md` and a clone in `repos/` (unregistered existing repo: register it first with `factory-add-repo` auto mode; repos the run creates are skipped) -> `run-stages.sh $T factory-research research "<those repos>"`, then re-run the plan once (`TRY=2`) and redo the `plan-meta.sh` steps. Never loop more than that once |
| plan_review | `run-stage.sh $T factory-plan-review plan_review`, then `## Plan gate` |
| grill | `run-stage.sh $T factory-grill grill` (human-interactive, so run it detached per `## Waiting`; exit 3 = no Herdr -> do the grill yourself following `skills/factory-grill/SKILL.md`; exit 4 = past the cap but the user is still in the grill tab: not a failure, never re-launch it, tell the user in one line and wait for `work/grill.json` with `pr-watch.sh --file`). Then require `plan-open.sh $T` == 0 and `plan-meta.sh` locked=true, and re-run `plan-meta.sh $T` -> `state.sh $T update '.repos=<repos>'` (the grill may change repos, waves, frontend). Worktrees are created per wave |

## Plan gate (after plan_review, before the grill)
Read `input.md`, then from `plan.md` the front matter, `## Goal`, `## Acceptance criteria`, `## Open questions` and the headings (`grep -n '^#' plan.md`). Check it as the lead who owns the outcome:
- the approach fits the requirement and its constraints (who uses it, what they can and cannot change, what must stay generic);
- every requirement has a testable criterion, and every number or limit has a reason;
- the repo list covers every repo that owns, configures or consumes the change.
Wrong approach or a factual error -> write `artifacts/plan-feedback.md` (what is wrong, evidence, what you expect instead), re-run the plan once with `TRY=<next> EXTRA="feedback=artifacts/plan-feedback.md"`, redo the plan row's `plan-meta.sh` steps, then plan_review again. A real product choice -> add it to `## Open questions` with your recommended answer, so the grill asks it.

## Wave loop
`state.sh $T wave-next` prints `<wave> <step> <repos...>` or `complete`. Progress comes from `work/<step>-<repo>.json` (a done `-t<n>` try counts), so never record it yourself: run the step for the listed repos, then ask `wave-next` again. Pass the repo list as one quoted string; `run-stages.sh` splits it.

Before a wave's `execute` step, prepare each listed repo: no clone at `repos/<repo>` -> take its `plan-meta.sh $T`.remotes entry (none: STOP, the plan is missing `remote:`), wait for it with a detached `pr-watch.sh --repo <owner/name>`, then register it by following `skills/factory-add-repo/SKILL.md` in auto mode (`<owner/name> auto`). Then `new-worktree.sh $T <repo> <branch>` for every listed repo (idempotent; includes harness-only repos).

| step | what the lead does |
|---|---|
| execute | `run-stages.sh $T factory-execute execute "<repos>"` |
| ui_test | Listed repos = this wave's frontend repos with `ui` not false (libraries are tested through their harness repo). `run-stages.sh $T factory-ui-test ui_test "<repos>"`. Per failed repo: `## Fix loop` with `artifacts/test-report-<repo>.md`, each fix followed by `TRY=<n> run-stage.sh $T factory-ui-test ui_test <repo>`. Summary starts with `AUTH_EXPIRED`: tell the user, run `ui-login.sh <dev_url>` (visible window), wait for "done", rerun that repo |
| code_review | `run-stages.sh $T factory-code-review code_review "<repos>"`. A frontend repo whose `work/code_review-<repo>.json` has `"changed":true`: rerun its ui_test once (next `TRY`, same fix loop) |
| ci_check | `run-stages.sh $T factory-ci-check ci_check "<repos>"`. Any `blocked` -> STOP (see `blocked.md`): a wave's PRs never open until every repo in it is green. Then `## Pre-PR gate` |
| pr | `LABEL=pr-w<wave> EXTRA="repos=<a,b>" run-stage.sh $T factory-pr pr`. Print the wave's rows of `artifacts/prs.md`, then start `## CI on open PRs` for them |
| merge | Only in `pr_mode: merge`. Repos with `coderabbit` true in `prs.md`: run the `factory-review` loop on their PRs first (they open ready, so CodeRabbit reviews them). On the wave's watcher lines: `review=APPROVED checks=GREEN` -> merge per `## Merging`; approval missing -> tell the user who must give it (from `approvals-<repo>.md` and decisions.md) and keep watching. `ALL MERGED/CLOSED`: any PR closed unmerged -> STOP and tell the user; else `worker-done.sh $T merge-w<wave> done "<n> merged"` |

## Pre-PR gate (after ci_check, before the wave's PRs)
Per repo read `artifacts/test-report-<repo>.md`, `review-<repo>.md` and `ci-check-<repo>.md`. Done means proven:
- every acceptance criterion for the repo has a passing scenario with its screenshot (a library change: screenshots from its harness app);
- no must-fix left open in the review, and nothing reported PASS without evidence.
A missing scenario or screenshot -> write a brief naming what to cover and rerun `TRY=<n> EXTRA="brief=<path>" run-stage.sh $T factory-ui-test ui_test <repo>`. A code gap -> `## Fix loop` with a brief, then rerun that repo's ui_test and ci_check (next `TRY`) before the `pr` step.

## Fix loop
Up to `caps.fix_tries` per repo: `EXTRA="mode=fix report=<path>" TRY=<n> run-stage.sh $T factory-execute fix <repo>`. The report is the failing report itself, or a brief you write to `artifacts/brief-<repo>-t<n>.md` when it needs context: what failed, evidence paths, the suspected cause if known, and what "fixed" means. Never put a brief inline in EXTRA. Still failing after the cap -> write `tasks/$T/blocked.md` (repo, tries, last report path) and STOP.

## CI on open PRs
An open PR is not done; green CI is. Start a detached `pr-watch.sh <owner/repo#n>...` for the wave's PRs (`## Waiting`) and act on each line: `checks=FAILING(<names>)` -> save the failure (`circleci-failures.sh` or `gh run view <id> --log-failed`) to `artifacts/ci-fail-<repo>-t<n>.md` and run `## Fix loop` with it. A check that fails the same way on the base branch (listed in `artifacts/ci-preexisting-<repo>.json`) is not the branch's: note it in the PR, don't fix it. Draft mode: stop the watcher once every PR shows `checks=GREEN` or only pre-existing failures.

Done (`complete`): tell the user only once every PR's checks are green or pre-existing. Draft mode, next steps for them: review the draft PRs, mark ready, run `/factory-review <id>` (CodeRabbit skips drafts). Merge mode: list what merged.

## Stalls
A worker running well past its stage's usual time (about 30 min; the grill excepted) or a watcher log that stops changing: look, don't wait. `herdr tab list` shows each tab by worker key with its agent status; a worker waiting on a dialog or question -> tell the user which tab.

## Lead autonomy
Decide yourself when the playbook, the locked plan or decisions.md answers it, or when you are highly confident. Log each call, and every user instruction that changes the run (scope, approach, approvers, what to skip), under `## Lead decisions` in `tasks/<id>/decisions.md` (`- <date>: <decision>. Why: <rationale>.`) right away: your chat gets compacted, the file does not. Tell the user in one line. Ask (one question, A/B/C, your pick marked) only for: low confidence, product or scope changes, anything that contradicts decisions.md, irreversible prod actions the plan does not list, approvals someone else must give (say who), and cap hits (fix_tries, review rounds, watcher timeout). This narrows the user's "always ask" reply rule for the factory lead only. Hard user rules (e.g. ask before creating Jira tickets) still win.

## Merging (`pr_mode: merge` only)
`plan-meta.sh $T`.pr_mode is `draft` unless the grill set `merge` (logged in decisions.md). In draft mode you never merge. In merge mode you merge a PR (`gh pr merge <n> --repo <o/r>` in the repo's usual style, e.g. `--squash`) only when both hold:
- GitHub allows it: approved per branch protection, every required check green (`pr-watch.sh` says `review=APPROVED checks=GREEN`), mergeable;
- the plan's approver for that repo (decisions.md) has approved, and anyone in `artifacts/approvals-<repo>.md` "Needs approval from" has too.
Never approve your own PR or ask a bot to; if an approval is missing, tell the user who must give it.

## Waiting (PRs, CI, repos, publishes, long stages)
Every wait goes through `scripts/pr-watch.sh`; never `sleep`, never ask the user to tell you when something happened.
- PRs and their CI: `pr-watch.sh <owner/repo#n>...`. A new repo: `--repo <owner/name>`. A package publish: `--npm <pkg@ver>...` (run it from the repo dir so its `.npmrc` picks the registry). A worker file: `--file <path>`. One line per state change; exit 0 when done, 3 at the 2 h cap (report a cap hit to the user).
- Anything that can outlive a few minutes runs detached and Monitor only tails its log (Monitor dies at 30 min, foreground Bash at 10): `nohup bash $ROOT/scripts/pr-watch.sh a/b#1 c/d#2 >> $ROOT/tasks/$T/work/watch-<label>.log 2>&1 &`, then Monitor `tail -n +1 -f <that log>`. Same for long `run-stage.sh`/`run-stages.sh` calls.
- Load Monitor's schema first: ToolSearch `select:Monitor`.
- Your Bash and Monitor commands run in **zsh**, not bash: an unquoted `$var` is not split into words, and `declare -A` does not exist. Write PR refs and repo names out as separate literal arguments, and put any loop logic inside a `bash` script, never inline.

## Upstream package PR merged
When the user says a PR in a published package repo is merged, follow `skills/factory/release.md` (standing authorization; covers that repo's bot release PR only).

Resume by following this playbook with the same task id: `state.sh next` picks up the first unfinished stage, then `wave-next` the first unfinished wave step; finished work never reruns. Execute resumes per slice from `work/progress-<repo>.txt`. A watcher from before a relaunch keeps writing its `work/watch-*.log`: tail it again rather than starting a second one.
