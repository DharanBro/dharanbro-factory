# dharanbro-factory

End-to-end dev pipeline: Jira key or plain-text idea -> research -> plan -> automated plan review -> deep grill (human) -> execute -> UI test -> code review -> draft PRs. Entry point: `skills/factory/SKILL.md`. Details: `README.md`, playbooks in `skills/`.

## Rules (all sessions, leads and workers)
- Self-contained: never read or edit anything outside this folder, except the repo checkouts under `repos/` and `tasks/` Sole exception: `scripts/usage.sh` (never a worker) reads the agents' own session logs in `~/.claude/projects` and `~/.codex/sessions` to total token usage.
- Handoff is via files in `tasks/<id>/`. Workers write detail to files, finish with `scripts/worker-done.sh`, and keep chat terse (caveman full: drop articles/filler/pleasantries, fragments OK; code, commits, PR text, and files under `tasks/` stay normal prose). The lead reads only `state.json` and `work/*.json` (<=300 char summaries).
- Invoke helper scripts as `bash <abs>/scripts/<name>.sh` so permissions match.
- Read only the files your stage lists as inputs. Prefer grep/targeted reads over whole files.
- Commits: Conventional Commits, Jira id (or idea slug) as scope, e.g. `feat(DP-1234): add status filter`. Never force-push; never push to the base branch.
- PR branches must always be up to date with master (base): before every push/PR and on every resume, `git fetch` and merge the base into the branch (merge, not rebase, since no force-push), resolve conflicts, re-run gates, then push.
- Unit tests must not be time-sensitive: no real clocks/timers, no sleeps, no tight timeouts, and no long loops of UI events (CI is slower than local; a 5s default timeout flaked in DP-6969). Use fake timers or deterministic waits, and keep each test small and fast. Never fix flakiness by raising a timeout.
- Start workers through `scripts/run-stage.sh`; the configured agent backend controls headless sessions or Herdr tabs.
- Draft PRs only.
- Harness, model, and effort are chosen per stage in `factory.yml`; do not change global agent settings.
- Tokens live in `secrets.env` (gitignored, loaded by `scripts/lib.sh`; template `secrets.env.example`). Use them only via scripts (e.g. `scripts/jira-attach.sh`); never print, log, or commit them.
- `repos.yml`, `repos/`, `tasks/`, `.browser-profile/` are local and gitignored.
