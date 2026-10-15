# dharanbro-factory

Jira key or idea in, draft PRs out. One folder per task, worktrees only for repos that change, a fresh short-lived worker per stage, handoff through files (that is where the token savings come from).

## Setup (once)
1. Needs: `git`, `gh` (logged in), `jq`, `ruby` (ships with macOS), `claude`, Node (for the browser test). Herdr optional.
2. `/factory-add-repo <git remote>` for each repo. Writes `repos.yml` (gitignored) and clones into `repos/`. See `repos.example.yml` for every field.
3. Frontend repos: keep a UI-testing doc inside the repo (how to run it + log in; path goes in `ui_test_doc`).
4. First UI test behind Auth0: `bash scripts/ui-login.sh <dev_url>`, log in once in the visible window, close it. The factory's own profile (`.browser-profile/`) keeps the session; later runs are headless.
5. Worktree folders are new git roots, so Claude asks "trust this folder" once per worktree. In Herdr the factory answers it for folders it created (`auto_trust_worktrees` in `factory.yml`). Headless runs never ask.
6. Tune models/effort/caps in `factory.yml` (per task: `tasks/<id>/factory.override.yml`).

## Use
```
/factory DP-1234            # or: /factory "add CSV export to the orders page"
/factory DP-1234            # again = resume at the first unfinished stage
/factory DP-1234 --from plan   # redo plan and everything after it
/factory-review DP-1234     # after you mark the draft PRs ready: CodeRabbit loop
```
In Herdr: one workspace per task (label = task id), a lead tab, one tab per worker. You only get pulled in for the grill, `blocked` workers, and when PRs are up. Outside Herdr: same pipeline with headless `claude -p` workers (the grill then runs in your session).

## Pipeline
`intake` (Haiku) -> `research` (per repo, parallel) -> `plan` (Opus) -> `plan_review` -> **`grill` (you, deep)** -> worktrees -> `execute` (per repo, in dependency waves, TDD) -> `ui_test` (frontend repos) -> `code_review` -> `ci_check` (repo's CI + local SonarQube gate reproduced, must be green) -> `pr` (draft, cross-linked, Jira comment) -> *you mark ready* -> `/factory-review`.

## Layout
```
factory.yml  repos.yml(local)  scripts/  .claude/skills/  repos/(base clones)  .browser-profile/
tasks/<id>/  state.json input.md research/ plan.md plan-review.md decisions.md work/ artifacts/ <repo>/(worktrees) blocked.md
```
`work/<key>.json` = each worker's 300-char result; the lead reads only those and `state.json`.

## Local SonarQube
`bash scripts/sonar-sync.sh` starts the `factory-sonar` container (http://localhost:9100) and mirrors the org gate + quality profiles for every repo with a `sonar:` block in `repos.yml` (needs `sonar auth login` for the org server). `ci_check` then runs `scripts/sonar-scan.sh <task> <repo>`: one Sonar project per task, base analysis back-dated to the merge-base so the gate judges only the branch's changes. Task projects and scan dirs older than 7 days (`SONAR_KEEP_DAYS`) are deleted on every scan, or run `bash scripts/sonar-scan.sh prune`. The embedded-DB banner in the UI is expected: the server is disposable, so re-run `sonar-sync.sh` after wiping the `factory-sonar-*` volumes.
