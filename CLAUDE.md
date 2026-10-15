# dharanbro-factory

End-to-end dev pipeline: Jira key or plain-text idea -> research -> plan -> automated plan review -> deep grill (human) -> execute -> UI test -> code review -> draft PRs. Entry point: `/factory <JIRA-KEY or idea text>`. Details: `README.md`, skills in `.claude/skills/`.

## Rules (all sessions, leads and workers)
- Self-contained: never read or edit anything outside this folder, except the repo checkouts under `repos/` and `tasks/`.
- Handoff is via files in `tasks/<id>/`. Workers write detail to files, finish with `scripts/worker-done.sh`, and keep chat terse. The lead reads only `state.json` and `work/*.json` (<=300 char summaries).
- Invoke helper scripts as `bash <abs>/scripts/<name>.sh` so permissions match.
- Read only the files your stage lists as inputs. Prefer grep/targeted reads over whole files.
- Commits: Conventional Commits, Jira id (or idea slug) as scope, e.g. `feat(DP-1234): add status filter`. End commit messages with `Co-Authored-By: Claude <noreply@anthropic.com>`. Never force-push; never push to the base branch.
- PR branches must always be up to date with master (base): before every push/PR and on every resume, `git fetch` and merge the base into the branch (merge, not rebase, since no force-push), resolve conflicts, re-run gates, then push.
- Unit tests must not be time-sensitive: no real clocks/timers, no sleeps, no tight timeouts, and no long loops of UI events (CI is slower than local; a 5s default timeout flaked in DP-6969). Use fake timers or deterministic waits, and keep each test small and fast. Never fix flakiness by raising a timeout.
- Delegate to Herdr agents by default (own tab via `herdr tab create` + `herdr agent start --kind claude`, see `herdr_spawn` in `scripts/lib.sh`), not the in-process Agent tool. Fall back only if Herdr is unavailable.
- Draft PRs only. PR body ends with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
- Model/effort per stage live in `factory.yml`; never change global Claude settings.
- Tokens live in `secrets.env` (gitignored, loaded by `scripts/lib.sh`; template `secrets.env.example`). Use them only via scripts (e.g. `scripts/jira-attach.sh`); never print, log, or commit them.
- `repos.yml`, `repos/`, `tasks/`, `.browser-profile/` are local and gitignored.
