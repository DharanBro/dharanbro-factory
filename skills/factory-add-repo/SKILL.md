---
name: factory-add-repo
description: Register a repo in the factory (repos.yml, local + gitignored) and clone it to repos/. Infers type, commands and UI-test doc from the clone and asks only for gaps. Usage `/factory-add-repo <git remote URL or owner/name>`.
---

`ROOT` = repo root. `repos.yml` is gitignored on purpose; never commit it.

1. Remote from the arg (`owner/name` -> `git@github.com:owner/name.git`; ask once if ambiguous). Name = last path segment without `.git`, lowercase.
2. Register + clone: `bash $ROOT/scripts/repo-set.sh <name> --remote <url>` (branch auto-detected from the clone).
3. Inspect `repos/<name>` cheaply: `package.json` (scripts, dependencies like react/next/express), lockfile (yarn/pnpm/npm), README head, CLAUDE.md/AGENTS.md, CI config (`.circleci/config.yml`, `.github/workflows/*.yml`, `.husky/`), docs for UI testing (`docs/ui-testing.md`, `TESTING.md`, grep "auth0|login|e2e"). Do not read source files.
4. Propose values: `type` (frontend if it ships a browser UI; library if published package; else backend), `description` (what the repo OWNS and who consumes it, 1-2 lines: research uses it to shortlist repos), `install`, `test`, `lint`, `typecheck`, `ci_checks` (the locally-runnable commands the repo's CI requires, per-workspace placeholders allowed; skip deploy/Sonar-upload jobs), and for frontend `dev_cmd`, `dev_url`, `ui_test_doc` (path inside the repo).
5. Ask the user ONLY about what you could not infer or are unsure of, one short batch, each with your recommended answer. Frontend with no UI-test doc: ask how the app is run and logged into locally; offer to leave `ui_test_doc` unset (the plan stage will then raise it in the grill).
6. Also ask: `coderabbit` on for this repo? (default: ask, since it only matters for the post-PR loop).
7. Sonar (local gate, runs in `ci_check`): project key = `sonar.projectKey` in the clone's `sonar-project.properties` (none -> skip sonar, say so). `coverage_cmd` = the command that writes the lcov file named in that properties file (usually the repo's `test` command if it already runs `--coverage`; else e.g. `pnpm exec vitest run --coverage`).
8. Save: `bash $ROOT/scripts/repo-set.sh <name> --type ... --desc "..." --install "..." --test "..." ...` (only flags you have values for, incl. `--sonar-key`/`--sonar-coverage-cmd`). Then, if a sonar key was saved, run `bash $ROOT/scripts/sonar-sync.sh <name>` to mirror the org gate + rules into the local factory-sonar (needs Docker and `sonar auth login`; on failure report it and move on, `ci_check` will list sonar as UNVERIFIED). Print the final entry as one line.

## Auto mode (`<owner/name> auto`, used by the factory lead for a repo its run created)
Same steps, but never ask the user:
- Step 5: anything you cannot infer stays unset; log each gap as a decision (`## Lead decisions` in `tasks/<id>/decisions.md`).
- Step 6: `coderabbit` is true if the clone has `.coderabbit.yaml` (or `.yml`), or the repo was created from a template (`gh api repos/<owner>/<name> --jq '.template_repository.name // empty'`) whose `repos.yml` entry has `coderabbit: true`. Otherwise false.
- Step 8: a failed `sonar-sync.sh` is noted and skipped, as in normal mode.
