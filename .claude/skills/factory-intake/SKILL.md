---
name: factory-intake
description: Factory worker. Normalize a Jira ticket or a plain-text idea into tasks/<id>/input.md. Launched by the factory lead, not by hand.
---

Inputs: `$TASK_DIR/input.md` (either `Jira: <KEY>` or raw idea text). Read nothing else.

1. Jira key: fetch with the Atlassian MCP (`getAccessibleAtlassianResources` for the cloudId, then `getJiraIssue`). Take summary, type, description, acceptance criteria, labels, last 5 comments, linked issue keys, Figma/Confluence links. Skip attachments and history.
2. Idea text: restructure it, invent nothing.
3. Overwrite `$TASK_DIR/input.md`, max ~60 lines:
   `# <title>` / `Source:` (KEY or idea) / `Type:` / `## Description` / `## Acceptance criteria` / `## Links` / `## Unknowns` (every gap or ambiguity, one line each; the grill asks about these).
4. Finish: `bash $ROOT/scripts/worker-done.sh $TASK $KEY done "<title>; N unknowns"`.
   Jira unreachable -> `blocked` with the error.

Atlassian tools: if `mcp__atlassian__*` returns 403 "app is not installed", use the `mcp__claude_ai_Atlassian__*` equivalents (same names, load via ToolSearch).
