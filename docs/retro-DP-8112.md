# Retro: DP-8112 run (2026-10-29 to 2026-10-30)

DP-8112 was the factory's first multi-wave run in merge mode: 13 repos, 3 of them created during the run, and PRs taken to merge instead of left as drafts. The user had to step in far too often. This file records each intervention, its root cause in the factory, and the proposed fix. Source report (local, gitignored): `tasks/DP-8112/artifacts/retro.md`, written by a read-only `factory-debug` worker and checked against files.

Status: proposals only. Nothing below is implemented yet, except the `debug` stage in `factory.yml`, which is uncommitted.

## Summary

16 interventions: 13 verified by the retro worker, plus 3 found after it ran (#14 to #16). 12 fixes remove all of them. The two biggest wins:

- **A background watcher plus a "never wait to be told" rule (F7).** The lead kept stopping until the user reported that a PR had merged.
- **A per-wave pipeline (F3).** Today PRs open only after every repo has passed every stage, which cannot work when wave 2 depends on wave 1 being merged.

Two fixes change user rules and need the user's decision: F4 (`AGENTS.md` "Draft PRs only") and F10 (narrowing the output style's "always ask" for the factory lead).

## Interventions

| # | What happened | Root cause | Fix |
|---|---|---|---|
| 1 | The lead passed the repo list to `run-stages.sh` as one quoted string, twice (research, code_review). Both failed with `missing dir .../<all repos joined>`. | `scripts/run-stages.sh:7` keeps a quoted list as one argument. The only check is per repo, in `run-stage.sh:26`, after launch. | F1 |
| 2 | The grill ended with "no status file", and the user had to tell the lead the plan was locked. | Not the 600 s Bash limit. The grill ran 8 h 12 min, hit `caps.grill_timeout_min: 480` (`factory.yml:31`), and `run-stage.sh:96-97` reported `failed` while the agent was still alive in its tab. The message also points to `work/grill.log`, which the Herdr branch never writes. | F2 |
| 3 | After wave 1 execute, the lead stopped to ask A/B questions. The user had to ask "why are PRs not raised" and "why are you stuck". | `skills/factory/SKILL.md:27-31` runs execute for all waves, then every later stage for all repos. The plan's merge sequence is prose the playbook never reads. | F3, F10 |
| 4 | The lead marked `execute` done after wave 1 and had to revert it. | `state.json` has one flat `.stages` map (`state.sh:10-11`), with nothing per wave or per repo. | F3 |
| 5 | `factory-pr` hardcodes draft PRs for every repo in `state.json`. The merge override and the wave scope had to be passed by hand through `EXTRA`, using `TRY` as a label. | `skills/factory-pr/SKILL.md:3,8,12,18`, and `AGENTS.md:14` "Draft PRs only". | F4, F11 |
| 6 | The plan bundled the template and `encore-ikea-apps` in one registry PR, with ikea created empty. The user corrected it: ikea must be created from the template, which needs content first. | `locus-repo-registry` was added by the plan and never researched. Its README (lines 107-108, 124) documents the template ordering. Plan review reads only `research/*.md`. | F5 |
| 7 | Approvers were found by trial: auto-approve skipped the PR (its `devops-admins` lookup returns 404), which cost a CODEOWNERS PR (#224), a Slack draft and two turns. | No skill or script reads `CODEOWNERS`, `AUTO_APPROVERS.txt` or branch protection. | F6 |
| 8 | The lead waited for the user to say PRs were merged. The user had to say "always use monitors". | The playbook only mentions Monitor in the upstream-release section, and the user's rule lives in memory, not the playbook. | F7 |
| 9 | `/factory-add-repo` was a manual human pause after each registry merge. | The factory has no automated path. `new-worktree.sh:6` also exits 1 for repos that don't exist yet, and the playbook creates every worktree right after the grill. | F8 |
| 10 | An actionlint failure in `encore-infra` that is also on master blocked the PR worker. Its summary said "unverified" while the file said `FAIL`. | `scripts/ci-run.sh:14-16` records `FAIL` with no comparison against the base branch. `factory-pr` blocks on any `FAIL`. | F9 |
| 11 | Too many A/B questions about pipeline mechanics the plan had already decided. | The output style says "every real choice goes to him", and the playbook never says which choices it has already made. | F10 |
| 12 | Monitor failed on its first call (schema not loaded), and chained `sleep` is blocked. | The playbook names no wait mechanism, and stage calls exceed the 10 min foreground Bash cap. | F7 |
| 13 | `factory-debug` had no stage in `factory.yml`, so the retro worker failed to start. The second attempt failed because `retro` went into the repo slot. | `run-stage.sh:8,12-15` takes model and effort from the stage name, which is also the key. | F11 |
| 14 | The first PR Monitor ran under zsh, which did not split the PR list, so it watched the wrong PR (`encore-ci#2510`). | Monitor commands run in the user's shell (zsh), not bash. An inline script assumed bash word splitting and `declare -A`. | F7 |
| 15 | The watcher reported `encore#5072` as failing, but the only failures were jobs from a run cancelled when a newer run started. The newer run passed on the same commit. | `statusCheckRollup` keeps checks from superseded runs. Classifying by "any CANCELLED" gives false failures. | F7 |
| 14b | It happened twice more: the CodeRabbit loop launch also hit zsh word splitting (`for a in "repo 645"; ... $a` passed one argument). Separately, a long loop run inside Monitor would be killed at the 30-min Monitor cap mid-fix. | Same as #14, plus Monitor's hard 30-min cap. | F7: long loops run detached (`nohup bash script >> log &`) and Monitor only tails the log, with args always passed explicitly to bash scripts. |
| 17 | The CodeRabbit loop on `encore-client-apps-template#1` went from 11 to 10 open threads after round 1, although every thread had been fixed or answered. Each round re-handled the same threads and used up the 5-round cap. | `scripts/cr-fetch.sh` counted every unresolved CodeRabbit thread. CodeRabbit resolves a thread only after it re-checks it, so threads we had already answered stayed in the count. | **Fixed during the run:** `cr-fetch.sh` now also requires the thread's last comment to be CodeRabbit's, so answered threads drop out until CodeRabbit replies again. Verified on PR #1: 8 unresolved, 4 waiting on us. |
| 16 | `infra-addons#307` and `locus-deployment-registry#2510` were mergeable with no review requirement, but the plan requires DevOps / Deployment Owners approval. The lead had to judge whether to merge. | The plan's approval rule is prose, and the PR state doesn't encode it. | F6, F10 |

## Fixes, ranked by interventions removed per effort (S=1, M=2)

1. **F7: watcher script plus waiting rule** (S, removes #8, #12, #14, #15). Add `scripts/pr-watch.sh <owner/repo#n>...`, a bash script with a `#!/usr/bin/env bash` shebang, always called as `bash scripts/pr-watch.sh`. It prints one line per state change and exits when everything is merged or closed. A `--repo <owner/name>` mode exits once the repo exists. It judges checks on the latest run per check name only, so superseded cancelled runs are ignored. Playbook rule: "Any wait on PR, CI, repo or publish: run the watcher in the background or under Monitor. Never ask the user to report state, never `sleep`. Load Monitor with ToolSearch `select:Monitor` before first use." A working draft of the script exists from this session.
2. **F3: per-wave pipeline and per-wave state** (M, removes #3, #4). Replace the execute..pr rows with a loop over waves: execute, then UI test (frontend repos in the wave), code review, CI check and PR. In merge mode, the loop watches until the wave is merged before starting the next. Per-wave status is derived from the existing `work/<stage>-<repo>.json` files through a new `state.sh <id> wave-next`. `.stages` is kept for intake through grill only.
3. **F1: argument flattening and `--wave`** (S, removes #1). In `run-stages.sh`, split arguments on whitespace after `shift 3` (repo names can't contain spaces, `repo-set.sh:9`). Add `--wave N` / `--all`, resolved from `plan-meta.sh`. Pre-check that every repo dir exists before starting any worker.
4. **F2: an interactive grill never "fails" while its agent is alive** (S, removes #2). For `interactive=1`, skip the deadline while `herdr agent get` succeeds. If the deadline hits with the agent alive, exit 4 ("still running") instead of `failed`, and name the tab instead of a log file.
5. **F9: compare failing checks with the base branch** (S, removes #10). In `ci-run.sh`, re-run a failing command in a throwaway worktree at `origin/<base>`. If it fails the same way there, record `PRE-EXISTING`, don't count it in the exit code, and list it under "Unverified locally" in the PR.
6. **F10: a "Lead autonomy" section in `skills/factory/SKILL.md`** (S, removes #11, part of #3 and #16). **Needs user decision.** Proposed text:

   ```
   ## Lead autonomy
   Decide yourself, no question, when the playbook, the locked plan or decisions.md already answers it:
   - next stage/wave, opening PRs for a finished wave, re-running a worker once after `no status file` / `agent start failed`;
   - marking a check UNVERIFIED when ci-run proved it fails identically on the base branch;
   - merging a PR in `pr_mode: merge` once it is approved and every required check is green;
   - registering a repo the run created (factory-add-repo, inferred values);
   - waiting: always a background watcher, never "tell me when".
   Ask the user (one question, A/B/C) only for: product or scope changes, anything that contradicts decisions.md, irreversible prod actions the plan does not list, an approval someone else must give (say who), and cap hits (fix_tries, review rounds, watcher timeout).
   ```

7. **F5: research every repo the plan adds** (S, removes #6). After `plan-meta.sh`, run research for any plan repo with no `research/<repo>.md`, then re-run plan once. Plan review gets a checklist line: "for repos that create repos, env branches or infra, read the README/CLAUDE.md for ordering rules and cite them".
8. **F11: commit the `debug` stage, add `LABEL`, add a doctor check** (S, removes #13, part of #5). Change `run-stage.sh:8` to `key="${LABEL:-$stage${repo:+-$repo}}${TRY:+-t$TRY}"`, so scope labels stop riding on `TRY`. `scripts/doctor.sh` fails when any "Factory worker" skill has no stage in `factory.yml`.
9. **F8: the lead runs add-repo after the repo exists** (M, removes #9). Before each wave, for every repo with no clone, wait with `pr-watch.sh --repo`, then run `factory-add-repo` with inferred values. Turn CodeRabbit on if the clone has `.coderabbit.yaml` or the template's entry has it. Ask only if neither applies. Move `new-worktree.sh` into the wave loop.
10. **F4: factory-pr scope and PR mode from the plan** (M, removes #5). **Needs user decision.** The plan front matter gets `pr_mode: draft|merge` (default draft, set to merge only by the grill). `factory-pr` takes `repos=<a,b>` and adds `--draft` only in draft mode. Merging stays with the lead: it merges when the PR is approved and every check is green, and never self-approves. `AGENTS.md:14` becomes "Draft PRs unless the locked plan sets `pr_mode: merge`".
11. **F6: approval facts per repo** (M, removes #7, part of #16). New `scripts/repo-rules.sh <task> <repo>`, which writes `artifacts/approvals-<repo>.md`. It covers:
    - the base branch's required reviews and checks;
    - the CODEOWNERS owners that match the diff;
    - `AUTO_APPROVERS.txt` entries, and whether the auto-approve path scopes cover the diff;
    - any plan-required approver.

    It runs in ci_check. `factory-pr` copies "needs approval from X" into `prs.md`. The lead merges only when both GitHub and the plan's approver are satisfied.

## Other stop points found

- **Lead launch:** `work/lead-launch.log` shows `agent start failed`, and nothing retries the detached handoff in `launch-lead.sh:39-43`.
- **Any failure stops the run:** playbook line 18 stops on every `failed`, including transient ones. F10 adds "retry once".
- **Startup dialogs:** `lib.sh:69-86` waits up to 10 min per worker for a human to clear a startup dialog, likely folder trust on new worktrees. This is an inference; it wasn't observed in DP-8112.
- **CodeRabbit loop:** `factory-review` assumes the user marks PRs ready. In merge mode they are ready from the start, so the lead can run the loop itself.

## Not verified

- The `devops-admins` team 404 was taken from the auto-approve job log. No direct `gh api orgs/locus-taxy/teams/devops-admins` call was made.
- Whether the Monitor schema error and the `sleep` block also happen under the codex harness.
- Whether F8's CodeRabbit inference matches org defaults for new client repos.
