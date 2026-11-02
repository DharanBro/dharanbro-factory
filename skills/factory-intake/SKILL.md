---
name: factory-intake
description: Factory worker. Normalize a Jira ticket or a plain-text idea into tasks/<id>/input.md. Launched by the factory lead, not by hand.
---

Inputs: `$TASK_DIR/input.md` (either `Jira: <KEY>` or raw idea text). Read nothing else.

1. Jira key: `bash $ROOT/scripts/jira.sh get <KEY>` prints summary, type, status, labels, description, acceptance criteria, last 5 comments, linked issues and remote links (Figma/Confluence). Jira text is wiki markup (`#` = numbered list). Skip attachments and history.
2. Idea text: restructure it, invent nothing.
3. Overwrite `$TASK_DIR/input.md`, max ~60 lines:
   `# <title>` / `Source:` (KEY or idea) / `Type:` / `## Description` / `## Acceptance criteria` / `## Links` / `## Unknowns` (every gap or ambiguity, one line each; the grill asks about these).
4. Finish: `bash $ROOT/scripts/worker-done.sh $TASK $KEY done "<title>; N unknowns"`.
   `jira.sh` fails -> finish `blocked` with its error; never invent ticket details.
