# Agent-neutral factory migration

## Goal

Keep the existing pipeline, task state, worktrees, and `work/<key>.json` handoff while removing the requirement to run Claude Code.

## Changes

1. Move factory playbooks from a vendor directory to `skills/` and shared rules to `AGENTS.md`. Pass both paths explicitly to every worker.
2. Configure multiple harnesses as argv arrays with stdin or final-argument prompt delivery. Give each stage a default harness and profiles keyed by harness, each with its model and effort; allow a profile-specific command when it needs different tools.
3. Keep Herdr optional. Select its agent kind and expand that stage's model and effort into backend arguments; leave startup approval dialogs to the user.
4. Remove vendor-specific CLI flags, model names, permission files, commit trailers, PR attribution, and Jira-tool fallback from the core and playbooks. Keep provider-specific invocation details in the named harness configurations.
5. Preserve the UI-test browser profile and publish a Playwright MCP config for agent-specific wrappers to consume.
6. Verify configuration parsing, shell syntax, headless dispatch, and the worker result contract with a local fake agent.

## Contract

An agent receives a prompt naming `AGENTS.md`, the stage playbook, task paths, and the required final `worker-done.sh` call. It must have access to the factory root and task worktree. The worker launcher considers `work/<key>.json` the authoritative result. For interactive stages without Herdr, the caller runs the playbook in its current session.

## Configuration boundary

`factory.yml` owns pipeline caps and `stages.<stage>.default` plus `stages.<stage>.agents.<agent>` profiles. Each named top-level harness in `agents:` owns its headless command, prompt delivery, and Herdr kind/arguments. The launcher substitutes profile values into those arguments without interpreting vendor model names or CLI permissions.

`agent_override` optionally routes all stages, including the Herdr lead, to one named harness. Each stage selects that harness's keyed profile. A task-specific override can change the whole task by setting only `agent_override`.

## Verification

- All shell scripts pass `bash -n`.
- The merged YAML configuration parses and selects the headless runner.
- A fake agent passes both stdin and final-argument prompt delivery, stage command overrides, path expansion, and the `work/<key>.json` result contract.
- Fake Claude/Codex harnesses verify stage-specific model and effort flags for headless and Herdr workers, plus Herdr lead startup.
- A one-line task override routes planning and execution to the same fake harness in either direction; a fake Herdr run also verifies the overridden lead and worker models.
- Keyed stage profiles preserve each harness's own model and effort in mixed and single-harness modes, verified with fake headless and Herdr launches.
- A live backend run remains an integration check for the machine where its CLI, Herdr kind, Jira integration, and browser tools are configured.
