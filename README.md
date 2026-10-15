# dharanbro-factory

Jira key or idea in, draft PRs out. One folder per task, worktrees only for repos that change, a fresh short-lived worker per stage, handoff through files (that is where the token savings come from).

## Setup (once)
1. Needs: `git`, `gh` (logged in), `jq`, `ruby`, the CLIs selected by your stages in `factory.yml`, and Node (for browser tests). Herdr is optional.
2. Follow `skills/factory-add-repo/SKILL.md` for each repo. It writes `repos.yml` (gitignored) and clones into `repos/`. See `repos.example.yml` for every field.
3. Frontend repos: keep a UI-testing doc inside the repo (how to run it + log in; path goes in `ui_test_doc`).
4. First UI test behind Auth0: `bash scripts/ui-login.sh <dev_url>`, log in once in the visible window, close it. The factory's own profile (`.browser-profile/`) keeps the session; later runs are headless.
5. Configure each harness under top-level `agents:`. Under each stage, set `default` to the normal harness and define its `agents:` profiles with `model` and `effort`. The example uses Claude for planning and Codex for implementation. Headless workers use the selected harness's command and prompt delivery; Herdr starts its configured `kind` with that stage's profile. CLI arguments may contain `{root}`, `{task_dir}`, `{cwd}`, `{model}`, and `{effort}`. Startup dialogs require a user response.
6. Configure Jira access for the intake/PR harness and browser tools for the UI-test harness. UI-test workers need Playwright connected to the factory's `.browser-profile/` Chrome profile. The factory writes `tasks/<id>/work/ui-mcp.json` and exports `FACTORY_UI_MCP_CONFIG`; use a stage-specific `stages.ui_test.agents.<agent>.command` wrapper or your agent's MCP settings to load it. Tune stage mappings and caps in `factory.yml` (per task: `tasks/<id>/factory.override.yml`).

Stage profiles are keyed by harness, for example:

```yaml
stages:
  plan:
    default: claude
    agents:
      claude: { model: opus, effort: high }
      codex:  { model: gpt-6-sol, effort: high }
```

Per-task overrides can change `stages.<stage>.default` or any `stages.<stage>.agents.<agent>` value. Older overrides using `stages.<stage>.agent`, `.model`, `.effort`, or `.models` need to move to this structure. Move old `worker_args` into the corresponding top-level harness command or Herdr arguments.

To use one harness for every stage, set `agent_override: codex` or `agent_override: claude` in `factory.yml`. Set it back to `null` for the normal mixed mapping. For one task, put the same single line in `tasks/<id>/factory.override.yml`. The override selects that harness's profile in every stage, including a newly launched Herdr lead. When switching an already running Herdr task, stop its current lead before relaunching it so two leads cannot advance the same state file.

## Use
```
Follow skills/factory/SKILL.md with DP-1234
Follow skills/factory/SKILL.md with DP-1234 --from plan
Follow skills/factory-review/SKILL.md with DP-1234
```
In Herdr: one workspace per task (label = task id), a lead tab, one tab per worker. Outside Herdr: the caller acts as lead, configured headless workers run each stage, and the grill runs in the caller's session. Both modes use the same state and worker-result files.

## Pipeline
`intake` -> `research` (per repo, parallel) -> `plan` -> `plan_review` -> **`grill` (you, deep)** -> worktrees -> `execute` (per repo, in dependency waves, TDD) -> `ui_test` (frontend repos) -> `code_review` -> `ci_check` (repo's CI + local SonarQube gate reproduced, must be green) -> `pr` (draft, cross-linked, Jira comment) -> *you mark ready* -> `factory-review`.

## Layout
```
factory.yml  AGENTS.md  repos.yml(local)  scripts/  skills/  repos/(base clones)  .browser-profile/
tasks/<id>/  state.json input.md research/ plan.md plan-review.md decisions.md work/ artifacts/ <repo>/(worktrees) blocked.md
```
`work/<key>.json` = each worker's 300-char result; the lead reads only those and `state.json`.

## Local SonarQube
`bash scripts/sonar-sync.sh` starts the `factory-sonar` container (http://localhost:9100) and mirrors the org gate + quality profiles for every repo with a `sonar:` block in `repos.yml` (needs `sonar auth login` for the org server). `ci_check` then runs `scripts/sonar-scan.sh <task> <repo>`: one Sonar project per task, base analysis back-dated to the merge-base so the gate judges only the branch's changes. Task projects and scan dirs older than 7 days (`SONAR_KEEP_DAYS`) are deleted on every scan, or run `bash scripts/sonar-scan.sh prune`. The embedded-DB banner in the UI is expected: the server is disposable, so re-run `sonar-sync.sh` after wiping the `factory-sonar-*` volumes.
