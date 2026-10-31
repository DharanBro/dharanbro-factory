---
name: factory
description: Run the end-to-end dev pipeline for a Jira key or a plain-text idea (research, plan, review, grill, execute, UI test, code review, draft PRs). Pass the task or idea and optional `--from <stage>`. The lead itself follows `skills/factory/lead.md`.
---

`ROOT` = this repo's root (two levels above this file). Run scripts as `bash $ROOT/scripts/<x>.sh`.

1. Task id: arg matches `^[A-Z][A-Z0-9]+-[0-9]+$` -> that key (`kind=jira`). Existing `tasks/<arg>` -> resume it. Otherwise an idea: `idea-<3-5 word kebab slug>`.
2. `task-init.sh <id>`. Idea: write the user's raw text to `tasks/<id>/input.md`. Jira: write `Jira: <KEY>` to it. If `--from <stage>`: `state.sh <id> reset <stage>`.
3. `launch-lead.sh <id>`:
   - `LAUNCHED`/`FOCUSED`: reply in ONE line ("<id> lead starting in this workspace (renamed <id>); this session exits when the turn ends, grill will notify you") and stop. Do not run more tools after it.
   - `INLINE` (no Herdr): you are the lead. Follow `skills/factory/lead.md` in this session.
