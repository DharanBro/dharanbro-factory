# dharanbro-factory

End-to-end dev pipeline: Jira key or plain-text idea -> research -> plan -> plan review -> grill (human) -> execute -> UI test -> code review -> CI check -> PRs. Entry point: `skills/factory/SKILL.md`; stage playbooks in `skills/`.

## Rules (all sessions, leads and workers)
- Self-contained: never read or edit anything outside this folder, except the repo checkouts under `repos/` and `tasks/`.
- Handoff is via files in `tasks/<id>/`. Workers keep chat terse, put detail in files, and finish with `scripts/worker-done.sh`. Files, code, commits and PR text are normal prose.
- Invoke helper scripts as `bash <abs>/scripts/<name>.sh` so permissions match.
- Read only the files your stage lists as inputs. Prefer grep/targeted reads over whole files.
- Commits: Conventional Commits, Jira id (or idea slug) as scope, e.g. `feat(DP-1234): add status filter`. Never force-push; never push to the base branch.
- Before every push and on every resume, `git fetch` and merge the base branch into the PR branch (merge, not rebase), resolve conflicts, re-run gates, then push.
- Tokens live in `secrets.env` (gitignored, loaded by `scripts/lib.sh`). Use them only through scripts (e.g. `scripts/jira.sh`); never print, log, or commit them.
- `repos.yml`, `repos/`, `tasks/`, `.browser-profile/` are local and gitignored.
