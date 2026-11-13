# DP-9217 retro: why #598 took 33 hours, 24 CodeRabbit rounds and 47 commits

Read-only. Times are IST unless marked Z. Sources: `decisions.md`, `work/cr-w2.log`, `work/*.json` + `*.usage.json`, briefs and reports in `artifacts/`, `gh` data for encore-ui-toolkit#598 and disco-ui#256, factory skills and scripts at `be2a2c6` plus the uncommitted working tree.

## 1. Top line
The biggest cost was **scope added after the PR opened**: the alert example, the review step, refactor B and, largest, a redesign of the record-swap code that **already existed on master** (master `FormRenderer.tsx:495-499`). Together they took about 6 of the 18 active hours, 17 commits and about 10 CodeRabbit rounds. Second, **the pre-PR gates let through most of what CodeRabbit later found**. The code review found 1 must-fix, then CodeRabbit raised 33 findings and the review-598 debug pass found 3 more must-fix bugs, and every late finding cost one round of about 17 minutes. Third, the lead **deferred 5 valid CodeRabbit threads on day 1**, which goes against the CLAUDE.md loop rule. The user reversed that on day 2, which cost about 1 h 40 m and 4 rounds (r6-r9). Fourth, the **race-condition drip (r18-r22)** happened because the record-swap design listed only synchronous writes, and the r19 worker skipped the async sweep its brief asked for. Tooling gaps (cr-fetch timeouts, a local Sonar scan that misses some server issues, Prettier churn) added about 2 h more.

## 2. Numbers

| What | Value |
|---|---|
| Wall clock, intake to retro | 33 h 19 m (11-11 14:23 to 11-12 23:42) |
| Overnight idle (waiting on user) | about 15 h 25 m (11-11 21:01 to 11-12 12:25) |
| Active time | about 18 h (day 1: 6 h 40 m, day 2: 11 h 17 m) |
| Intake, research, plan, grill | 48 m (14:23 to 15:11) |
| Execute both repos to #598 opened | 1 h 44 m (15:11 to 16:55) |
| Day 1 after PR: alert example, 2 UI-test bug fixes, ci_check | 1 h 49 m |
| Day 1: CodeRabbit r1-r5, Sonar, cap decision | about 2 h 15 m |
| Day 2: re-opened deferred threads r6-r10 | 1 h 40 m (13:00 to 14:42) |
| Day 2: review-598, user decision, refactor B | 3 h 25 m (14:43 to 18:08; mostly the wait for the user's pick, inferred) |
| Day 2: r11-r12 after refactor | 55 m |
| Day 2: review step (scope add), t8 failure, fix | 1 h (19:04 to 20:04) |
| Day 2: Sonar s17 (with the lead edit and its revert) | 35 m |
| Day 2: record-swap design and race drip r18-r22, to clean r23 | 2 h (20:46 to 22:44) |
| Day 2: Sonar s23 + s25, r24 TIMEOUT | 50 m |
| #598 commits | 47 = 45 code + 2 merges from master |
| Commit split | 7 slices, 1 code review, 4 alert example (2 of them formatting reverts), 3 UI-test fixes, 7 Sonar, 19 CodeRabbit, 2 refactor B, 1 review step, 1 generated-file cleanup |
| Commits made by the lead itself (Opus trailer, not a worker) | 8: be423f43, d299830f, a0d6d950, 80f6003d, 21e778cb, 7b45a5b1, bf69fea3, 36a2406a |
| CodeRabbit fetch rounds (lead numbering) | 24 |
| Reviews that raised new findings | 14 (13 with inline comments, 1 outside-diff only) |
| Findings | 30 inline (22 major, 8 minor) + 3 outside-diff = 33 |
| Findings per review | 9, 2, 3, 3, 1, 4, 1, 1, 1, 2, 2, 1 (plus outside-diff 2 and 1) |
| Inline threads by area | server errors 10, step resolution 7, async/record lifecycle 8, a11y 4, review step 1 |
| Threads ending in a code change vs reply only | 29 vs 1 (4548201907, already covered by 121c46f8) |
| Our thread replies | 39 |
| Rounds with 0 new findings | about 10 (r2-r5 replies only, r6 TIMEOUT, r11 premature 0, r23, r24 TIMEOUT, others) |
| Time per race round r18-r22 | about 17 m: worker 7-8 m, UI test 1.5 m, 120 s sleep, CodeRabbit 5-7 m |
| PR size | +5,908 / -1,717 in 39 files; ignoring whitespace +5,021 / -829 |
| Prettier churn | about 3,200 of about 7,600 changed lines (review-598.md:27, Prettier-normalised diff). First FormRenderer commit 26ceb70f: 2,152 lines raw, 356 real |
| Workers | 79 runs: Sonnet 69, Opus 7, Haiku 3; 118 M tokens (mostly cache reads), 700 k output. Lead tokens not recorded |
| UI test runs after the review step | t10-t17: 8 runs, all 12/12 pass |
| disco-ui#256 (patterns only) | +354 / -73, 21 commits, 10 CodeRabbit inline findings, about 10 rounds, merged 11-12 13:49Z |

## 3. What went wrong

| # | What went wrong | Avoidable by factory? | Root cause (file:line) | Fix (file + exact change) | Effort | Saves (estimate) |
|---|---|---|---|---|---|---|
| 1 | **Race drip r18-r22.** Each round found one more async completion that could land on a new controller. Lead's account is partly wrong: the sweep was not first asked in r22. `brief-toolkit-r19.md` already said "every async completion (entity-select prefill, row prefill, ref hydration effect, aggregate figures ...; grep for `await` and `.then(`)". Worker commit 6271543d guarded only the prefill paths; hydration `.then` and aggregates were left for r22 (ecf9f757). The lead's gate on r19 did not check the listed sites | partly. CodeRabbit was right each time, but the design and gate could have caught them in 1-2 rounds | `design-record-swap.md` lists only synchronous write sites (Facts, line 9); no inventory of async completions. `skills/factory-execute/SKILL.md:28` (coderabbit mode) has no sweep rule. `skills/factory/lead.md` gate has no "check every site the brief listed" step | (a) `skills/factory-debug/SKILL.md`: when the question is a state or lifecycle design, the report must contain a table: every `await`, `.then(`, effect cleanup and callback in the touched files, what each mutates, and the guard it gets. (b) `skills/factory-execute/SKILL.md:28` append: "For each valid finding, grep the repo for the same pattern and fix every site; list `sites checked: <file:line ...>` in your summary." (c) `skills/factory/lead.md` (gate text): "When a brief lists sites, check the diff touches each one (`git show <sha> \| grep`) before accepting." | S | 3 rounds, about 1 h |
| 2 | **Scope added after the PR opened.** Alert example (day 1, user ask), review step (day 2, user picked B), refactor B (from review-598), and the record-swap redesign of master code (CodeRabbit 4550874742 on code already on master, user picked B). Each started new CodeRabbit rounds on a PR that was already 5k lines | partly. The user chose each one; the factory never offered "separate PR" with a cost estimate | `skills/factory/lead.md:57` treats scope changes as an A/B/C question but gives no default for "open a follow-up PR". The 125 entry in decisions.md asked about the record swap with no cost estimate | `skills/factory/lead.md` `## Lead autonomy`: "Scope added to an open PR, or a review finding on code that is unchanged from the base branch: option A is always a separate PR from the base branch, with an estimate (rounds, hours) for doing it inside." **Needs user decision** (changes how scope questions are framed) | S | 2-5 h on a run like this |
| 3 | **Deferred CodeRabbit findings, then reversed.** Day 1: 5 threads on #598 (4537388727, 4537388756, 4537388809, 4537388817, 4538655723) answered as follow-up or out of scope. User on day 2: "Why are you not fixing the issue mentioned by coderabbit?" All 5 were then fixed in r6-r9 | yes. User's CLAUDE.md says a comment that needs a code change gets the change | `skills/factory-review/SKILL.md:12` and `skills/factory-execute/SKILL.md:28` allow "you disagree with reason -> reply" with no limit on deferring valid findings | `skills/factory-execute/SKILL.md:28`: "A valid finding is fixed in this PR. Reply without a fix only when existing code already handles it (say where). Never answer a valid finding with 'follow-up' or 'out of scope' unless decisions.md records the user's OK for that thread." Same line in `skills/factory-review/SKILL.md` step 2 | S | about 1 h 40 m and 4 rounds |
| 4 | **Pre-PR review missed most issues.** code_review found 1 must-fix (62d6b509); CodeRabbit r1 then raised 9 (8 valid) and later reviews 24 more; review-598 found 3 must-fix bugs with scratch tests | partly. Some findings came from later scope, but r1's 9 and review-598's 3 were all in the original diff | `skills/factory-code-review/SKILL.md:6` reviews the raw diff, which for FormRenderer was 2,152 lines with 356 real; `:9` has no lifecycle check for stateful code; `:15` caps at 2 rounds | `skills/factory-code-review/SKILL.md`: (a) review `git diff -w origin/<base>...HEAD`, and when a file is mostly reformat, the diff of both sides through the repo's formatter; (b) add: "For each new piece of state or store, list how it is created, updated and reset on: record swap, re-render with equal data, unmount, hidden/disabled/skipped field, list row add/remove, async completion after any of these. A missing path is must-fix." Optional: run `coderabbit review --plain` (CodeRabbit CLI) locally before the PR step. **CLI option needs user decision** (new tool, account) | M | 4-6 rounds |
| 5 | **Local Sonar missed server issues** (s23 and s25). S1541 is reported on the function's first line, which the branch did not change; s23's helper split also added a `??` chain that raised DiscoUIJsonField from 11 to 13 | yes | `scripts/sonar-scan.sh:88-89` keeps an issue only if its line is inside a changed hunk; `:84` also limits to `inNewCodePeriod=true` | `scripts/sonar-scan.sh`: after the base scan, save its unresolved issues to `$W/base-issues-$mb.json` (key: rule, path, message). Verdict = issues on changed lines, plus issues in changed files whose key is not in the base file (drop `inNewCodePeriod=true` for that second query). Add a case to `scripts/tests/` | S-M | 2 Sonar rounds, about 50 m |
| 6 | **cr-fetch TIMEOUT** in r1, r6, r24, and the pause in r23 | yes | `scripts/cr-fetch.sh:22`: done only when a review object exists for the head sha. CodeRabbit posts none when an incremental review has nothing new. `:26-27`: pause text is searched in comments **created** after the last commit, but the "Reviews paused" notice is an edit of the walkthrough comment created 11-11 11:25Z (6794548133, updated to 11-12 18:06Z), so it never matches | `scripts/cr-fetch.sh`: (a) also stop when the head commit's CodeRabbit status in `statusCheckRollup` is SUCCESS or FAILURE (the chain already reads this as "coderabbit status: pass"); (b) match the pause text on `updatedAt > committedDate`, and on pause post one `@coderabbitai review` and keep waiting | S | about 1 h (3 x 20 m timeouts) |
| 7 | **No-op rounds r2-r5.** r2: the r1 worker pushed 8 fixes without replying, so all 9 threads were listed again. r3-r5: CodeRabbit's last reply on 4537388727 was "Understood. We can address focus management ... in a follow-up", which counts as open | yes | `scripts/cr-fetch.sh:35` counts a thread as open when CodeRabbit wrote last, even an acknowledgement. `skills/factory-execute/SKILL.md:28` does not say to reply on fixed threads (decisions.md 20:25 follow-up never landed) | `scripts/cr-fetch.sh:35`: skip threads whose last CodeRabbit comment matches `Review thread resolved\|in a follow-up\|mark this finding as addressed\|I consider`. `skills/factory-execute/SKILL.md:28`: "Reply on every thread in the same round, fixed or not, naming the commit." | S | 4 rounds; small in time (about 25 m) but they used 4 of the 5-round cap and forced a cap decision |
| 8 | **Lead edited repo code.** Lead's account says once. It was 8 commits on #598 (table above) plus 541c2f8 on #256. Two of them fixed real bugs the lead found at a gate (21e778cb, 36a2406a) | yes | `skills/factory/lead.md:5` says "Don't read code or worker logs yourself" but nowhere says the lead must not edit, commit or push. The rule logged in decisions.md (s17 entry) never reached the playbook | `skills/factory/lead.md:5` append: "Never edit, commit or push repo code, not even a one-line fix or a revert. A gap you find at a gate goes to a `factory-execute` worker with a brief." | S | user friction; keeps gate fixes tested by TDD |
| 9 | **`run-stage.sh` LABEL failures** for review-598 and r18 (each retried about 20 s later) | yes. DP-8112 F11 landed partly: `LABEL` and the doctor stage check exist; the stage argument is still easy to get wrong | `scripts/run-stage.sh:17`: an unknown stage gives "missing agent, model for 'claude'", which blames the agent, not the stage. The exact command the lead ran was not logged (inference: label passed as stage) | `scripts/run-stage.sh:17`: if `.stages[$stage]` is null, print `unknown stage '$stage' (valid: <keys>); use LABEL=<name> for a custom key` and exit 2 | S | about 1 m each; mainly clarity |
| 10 | **Worker did not push (r19b)** | yes | `skills/factory-execute/SKILL.md:6` "Never push (the PR stage does)" conflicts with `:25` (fix mode pushes) and `:28` (coderabbit mode pushes). A brief-only run has no mode, so line 6 wins (inference) | `skills/factory-execute/SKILL.md:6`: "Never push before the PR exists. Once the branch has an open PR, every run ends with `git push` (plain, never force)." | S | 1 lead step per occurrence |
| 11 | **Prettier churn**: about 3,200 lines because lint-staged formats whole files that master never formatted | partly | Repo hook, not the factory. The factory has no step to catch it before the first commit; decisions.md 11-11 follow-up ("revert hook-reformatted files") never landed | `skills/factory/lead.md` before a wave's execute: run `npx prettier --check` on the plan's touched files at the base commit; if any fail, ask the user to open a format-only PR on the base branch first (skip-changeset, `.git-blame-ignore-revs`). **Needs user decision** (touches master of a shared repo) | M | review noise; indirectly #4 |
| 12 | **Generated files committed** (54 tsc-emitted config .js/.d.ts in b9b0b1d5, removed in 80f6003d) | yes | `skills/factory-execute/SKILL.md` has no pre-commit check (decisions.md r6 follow-up never landed) | `skills/factory-execute/SKILL.md` all-modes list: "Before each commit, `git diff --cached --stat`: unstage generated files (compiled .js/.d.ts next to sources, dist, coverage) and any file the fix did not mean to touch." | S | 1 commit and a CodeRabbit re-trigger |
| 13 | **Gate noise**: playground multi-step e2e flakes about 1 in 4 on baseline; local `coverage_cmd` (`pnpm test`, whole monorepo) fails in unrelated schedule-view on every Sonar run | partly | `repos.yml` encore-ui-toolkit `sonar.coverage_cmd: pnpm test` (local file). The e2e flake is a repo issue | `repos.yml`: `coverage_cmd` scoped to touched packages, e.g. `pnpm turbo run test --filter=...[origin/master]`. Raise the e2e flake as its own ticket (repo, not factory) | S | a few minutes per Sonar run; fewer "known flake" reruns |
| 14 | **UI test caught what execute missed** (t8: JSON field editable on the review step; t4/t5 on day 1: Next into the last step submitted, no active step after Back) | no. This is the gate working; execute does not open a browser by design | none | keep | none | none |
| 15 | **Serial chain overhead**: worker, then UI test, then 120 s sleep, then CodeRabbit poll. t10-t17 all passed | partly | lead's chain, not a script | `skills/factory-review/SKILL.md` step 2: run the UI test in parallel with the CodeRabbit wait, and only when the fix touched renderer or component files; drop the fixed 120 s sleep (cr-fetch already waits on the sha) | S | about 3 m per round, about 0.5 M tokens per skipped UI run |
| 16 | **r11 worker reported "3 threads replied"** but threads 4550874754, 4550874763 and 4550874771 have no inline reply | yes | the worker summary is not checked against GitHub | covered by #7's reply rule; the lead's gate checks `gh api .../pulls/<n>/comments` for a reply per thread | S | avoids a re-list round |

## 4. Fixes ranked by saving per effort
1. **#3 No deferring valid findings** (`factory-execute/SKILL.md:28`, `factory-review/SKILL.md`). S, about 1 h 40 m.
2. **#6 + #7 cr-fetch: stop on the CodeRabbit status, see edited pause notices, skip acknowledged threads; workers reply on every thread.** S, about 1 h and 3-4 rounds.
3. **#1 Async inventory in design reports, sweep rule in coderabbit mode, lead checks listed sites.** S, about 1 h.
4. **#2 Separate PR as default option A for added scope or base-branch findings.** S, 2-5 h. **Needs user decision.**
5. **#5 Sonar verdict against base issues, not only changed lines.** S-M, about 50 m.
6. **#4 Lifecycle check and whitespace-free diff in code review.** M, 4-6 rounds. CodeRabbit CLI pre-PR part **needs user decision**.
7. **#8 Lead never edits repo code** (playbook text). S.
8. **#10 Push rule**, **#12 staged-file check**, **#9 run-stage message**. S each, small savings.
9. **#15 UI test only when UI files changed, in parallel with the CodeRabbit wait.** S.
10. **#13 Scoped coverage_cmd.** S.
11. **#11 Format-only base PR before execute.** M. **Needs user decision.**

## 5. What worked and should stay
- **UI tests on the real alert form** found 3 library bugs (auto-submit on Next, lost active step, editable JSON on Review) that unit tests and CodeRabbit did not.
- **Read-only Opus debug passes** (review-598, design-record-swap, design-review-step) proved bugs with scratch tests before anyone changed code; review-598 found 3 must-fix bugs that the first 10 CodeRabbit rounds had not.
- **TDD in fix briefs**: most fixes came with a test that failed first, and the lead checked "fails on old code" at gates (21e778cb, d18).
- **The lead's gates found real bugs**: the table-cell alias (21e778cb), heldByRef not reset (f18896f9), and 6 more sites with the same live-box gap in r18. These should go to a worker, not be fixed by the lead.
- **Sha matching in cr-fetch** (from #10) stopped a stale review being read as current.
- **decisions.md** kept a full, timestamped record; this retro could be checked against it line by line.
- **Splitting #256 into its own task** (DP-9217-256) let the toolkit work continue without waiting.

## 6. Facts, inferences, and what I could not verify
**Facts (seen in files or GitHub):** all counts in section 2 except the ones marked below; commit authorship from `Co-Authored-By` trailers; the r19 brief text and the 6271543d / ecf9f757 diffs; cr-fetch and sonar-scan logic at the lines cited; the walkthrough comment's created and updated times; master `FormRenderer.tsx:495-499` writes refs during render; none of the day-1 factory follow-ups in decisions.md (reply on every thread, generated-file check, revert hook reformat, volta PATH aside) are in the skills.

**Inferences:**
- The 3 h 25 m review-598-to-refactor block is mostly the wait for the user's pick. Brief file times (refactor-b brief at 18:02) suggest it, but the worker's start time was not logged.
- The `run-stage.sh` failures came from passing the label as the stage; the exact command was not logged.
- r19b did not push because of `factory-execute/SKILL.md:6`; the worker's reasoning was not saved.
- The "saves" column is an estimate from the per-round time (about 17 m) and the rounds each fix would have removed.
- The share of the 33 findings that a stronger pre-PR review would catch is a guess (4-6 rounds).

**Could not verify:**
- Lead token use and the lead's own wait time (not recorded in `work/`).
- The exact moment CodeRabbit's pause notice appeared (the walkthrough comment has been edited since; only its current text is visible).
- Whether the org Sonar PR analysis uses "not in target branch" issue tracking exactly as proposed in #5. The fix matches what was observed (S1541 on unchanged lines flagged on the server), but I did not run the patched script.
- Day-1 CodeRabbit deferral replies: the reply text on GitHub no longer reads as a deferral for all 5 (some were later edited or followed by fix replies); the deferral itself is from decisions.md 20:10, 20:45, 21:30 and the 11-12 entries.

## 7. Status of the fixes
| Fix | Commit | Status |
|---|---|---|
| #3 no deferring valid CodeRabbit findings | ef4ba14 | done |
| #7 + #16 reply on every thread, lead gate checks replies | c582581 | done |
| #6 + #7 cr-fetch: status stop, pause re-trigger (`CR_NO_POST=1` disables posting), ack filter | 6b181fa, 1324976 | done |
| #1 async inventory, sweep rule, lead checks listed sites | 022bd67 | done |
| #4 (a)+(b) whitespace-free diff, state lifecycle checklist | c25f430 | done |
| #8 lead never edits repo code | d125458 | done |
| #10 push once a PR exists, #12 staged-file check | b193fda | done (one commit for both) |
| #9 run-stage unknown stage message | 60c449e | done |
| #15 UI test only for UI fixes, parallel, no sleep | bc5a353 | done |
| #13 scoped `coverage_cmd` in local `repos.yml` | not committed (gitignored) | done |
| #2 separate PR as default option A | | pending (owner decision) |
| #4 CodeRabbit CLI, as a pre-push gate instead of pre-PR (CLI 0.4.0 `review --agent`) | a23f0b2 | done |
| Retro 2 gap 1: execute workers could push without Sonar or review (`push-gate.sh`; `worker-done.sh` fails `done` without a gate record for the pushed sha; execute, ci-check and lead playbooks) | a23f0b2 | done |
| Retro 2 gap 2: local Sonar verdict missed S1541/S3776 on a function's unchanged first line (new `sonar-verdict.py`: changed lines or flow locations, plus new issues in changed files vs the base scan) | 8b9e67f | done |
| #5 Sonar verdict against base issues, plus flow locations (verdict section only, owner's `sonar_hold` lines untouched) | 8b9e67f | done |
| #11 format-only base PR | | pending (owner decision) |
| Owner request: mandatory design review for frontend work | c71b8a7 | done |
