# dharanbro-factory

Jira key or idea in, draft PRs out. One folder per task, worktrees only for repos that change, a fresh short-lived worker per stage, handoff through files (that is where the token savings come from).

## Setup (once)
1. Needs: `git`, `gh` (logged in), `jq`, `ruby`, `curl`, `python3`, the CLIs selected by your stages in `factory.yml`, and Node (for browser tests).
2. Recommended: [Herdr](https://herdr.dev/#install). Install or update on macOS/Linux with `curl -fsSL https://herdr.dev/install.sh | sh` (installs to `~/.local/bin`; other methods: https://herdr.dev/docs/install/). Start the factory from a Herdr pane: each task gets its own workspace and every worker its own tab, so you can watch or step into any stage. Without Herdr, workers run headless in the background (`runner: auto` picks Herdr whenever you are inside it).
3. [Headroom](https://docs.headroomlabs.ai) (context compression proxy, cuts token usage): `pipx install "headroom-ai[proxy]"`, then `headroom init -g claude` and `headroom init -g codex` so every agent launch, workers included, routes through it. A shell alias like `claude='headroom wrap claude'` only covers your own sessions; the factory starts workers without your shell aliases. Check with `headroom doctor`; update with `headroom update`.
4. Claude plugin the workers rely on: `ponytail` (lean code in execute, fix, review). Install at user scope: workers run inside other repos' worktrees, so this folder's project settings do not reach them.
   ```
   claude plugin marketplace add DietrichGebert/ponytail
   claude plugin install ponytail@ponytail
   ```
5. Copy `secrets.env.example` to `secrets.env`, `chmod 600 secrets.env`, and fill in the Jira and CircleCI tokens.
6. Follow `skills/factory-add-repo/SKILL.md` for each repo. It writes `repos.yml` (gitignored) and clones into `repos/`. See `repos.example.yml` for every field.
7. Frontend repos: keep a UI-testing doc inside the repo (how to run it + log in; path goes in `ui_test_doc`).
8. First UI test behind Auth0: `bash scripts/ui-login.sh <dev_url>`, log in once in the visible window, close it. The factory's own profile (`.browser-profile/`) keeps the session; later runs are headless.
9. Configure each harness under top-level `agents:`. Under each stage, set `default` to the normal harness and define its `agents:` profiles with `model` and `effort`. The example uses Claude for planning and Codex for implementation. Headless workers use the selected harness's command and prompt delivery; Herdr starts its configured `kind` with that stage's profile. CLI arguments may contain `{root}`, `{task_dir}`, `{cwd}`, `{model}`, and `{effort}`. Startup dialogs require a user response.
10. Jira: intake and PR workers use `scripts/jira.sh` with the `ATLASSIAN_*` tokens from step 5. UI tests: the factory writes `tasks/<id>/work/ui-mcp.json` (Playwright on Chrome for Testing with the factory's `.browser-profile/`) and `factory.yml` hands it to Claude; other harnesses load it through a `stages.ui_test.agents.<agent>.command` wrapper (`FACTORY_UI_MCP_CONFIG` holds the path). Tune stage mappings and caps in `factory.yml` (per task: `tasks/<id>/factory.override.yml`).
11. Run `bash scripts/doctor.sh` and fix anything marked MISSING.

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
In Herdr: one workspace per task (label = task id), one tab per worker. Launched from a Herdr pane, the factory reuses that workspace: renames it to the task id, exits the calling session, and starts the lead fresh in the same pane (log: `work/lead-launch.log`). Outside Herdr: the caller acts as lead, configured headless workers run each stage, and the grill runs in the caller's session. Both modes use the same state and worker-result files.

## Pipeline
`intake` -> `research` (per repo, parallel) -> `plan` -> `plan_review` -> **`grill` (you, deep)** -> then per dependency wave: worktrees -> `execute` (per repo, TDD) -> `ui_test` (frontend repos) -> `code_review` -> `ci_check` (repo's CI + local SonarQube gate reproduced, must be green) -> `pr` (draft unless the plan sets `pr_mode: merge`; cross-linked, Jira comment) -> in merge mode, watch until the wave is merged -> next wave. Draft mode ends with *you mark ready* -> `factory-review`. Wave progress comes from `state.sh <id> wave-next`.

## Layout
```
factory.yml  AGENTS.md  repos.yml(local)  scripts/  skills/  repos/(base clones)  .browser-profile/
tasks/<id>/  state.json input.md research/ plan.md plan-review.md decisions.md work/ artifacts/ <repo>/(worktrees) blocked.md
```
`work/<key>.json` = each worker's 300-char result. The lead (`skills/factory/lead.md`) reads those, `state.json` and the short reports at its gates (plan, pre-PR), never code or worker logs.

## Local SonarQube
`bash scripts/sonar-sync.sh` starts the `factory-sonar` container (http://localhost:9100) and mirrors the org gate + quality profiles for every repo with a `sonar:` block in `repos.yml` (needs `sonar auth login` for the org server). `ci_check` then runs `scripts/sonar-scan.sh <task> <repo>`: one Sonar project per task, base analysis back-dated to the merge-base so the gate judges only the branch's changes. Task projects and scan dirs older than 7 days (`SONAR_KEEP_DAYS`) are deleted on every scan, or run `bash scripts/sonar-scan.sh prune`. The embedded-DB banner in the UI is expected: the server is disposable, so re-run `sonar-sync.sh` after wiping the `factory-sonar-*` volumes.

## Token usage

Where tokens go: every turn re-reads the whole session context, so two things dominate. The lead runs on Opus with a 200k compaction window (`autoCompactWindow`; Opus defaults to 1M), so its long chat stays small. Worker stages marked `lean: true` start without the skill listing, most plugins and your MCP servers (`claude-worker-settings.json`, `worker-mcp.json`), which removes about 20K tokens from every turn. Edit `claude-worker-settings.json` when you install a plugin workers should not load.

`run-stage.sh` stamps each worker prompt with `RUN=<uuid>`; after the worker exits, `scripts/usage.sh` finds the Claude or Codex log whose first prompt carries the marker and writes `tasks/<id>/work/<key>.usage.json` (input / cached / cache_write / output / total). Claude subagent logs are included. Report per task, lead included: `bash scripts/usage.sh report <id>`. Not counted: an inline lead (the session you typed in) and any final reply a worker emits after its tab is closed.
