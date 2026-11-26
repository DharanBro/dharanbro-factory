#!/usr/bin/env bash
# run-stage.sh with stub herdr/sleep: a grill past its deadline exits 4 while its agent lives, fails (naming the
# tab) once the agent is gone; LABEL replaces the stage-repo part of the key; lean stages get herdr.lean_args.
. "$(dirname "$0")/lib.sh"
R=$(fake_root run-stage.sh); B="$R/bin"; mkdir -p "$B" "$R/skills/factory-grill" "$R/skills/factory-debug" "$R/skills/factory-intake" "$R/tasks/t"
touch "$R/skills/factory-grill/SKILL.md" "$R/skills/factory-debug/SKILL.md" "$R/skills/factory-intake/SKILL.md" "$R/scripts/usage.sh"
printf 'runner: herdr\ncaps: {grill_timeout_min: -1, stage_timeout_min: -1}\n' > "$R/tasks/t/factory.override.yml"
printf '#!/usr/bin/env bash\n:\n' > "$B/sleep"
cat > "$B/herdr" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "tab create") echo '{"result":{"root_pane":{"pane_id":"p1"},"tab":{"tab_id":"w:t1"}}}' ;;
  "tab list") echo '{"result":{"tabs":[]}}' ;;
  "agent start") shift 2; printf '%s\n' "$@" > "$(dirname "$0")/start-args" ;;
  "agent prompt") printf '%s' "$4" > "$(dirname "$0")/prompt" ;;
  "agent get") [ -f "$(dirname "$0")/dead" ] && exit 1; echo '{"status":"working"}' ;;
esac
exit 0
EOF
# hc (new Herdr app) stubs: a terminal is live once run with its prompt (the last argument); with "dead", it then finishes.
cat > "$B/hc" <<'EOF'
#!/usr/bin/env bash
D=$(dirname "$0"); cmd=$1; shift
case "$cmd" in
  run) printf '%s\n' "$@" > "$D/hc-run-args"; printf '%s' "${@: -1}" > "$D/prompt"; while [ $# -gt 0 ]; do [ "$1" = --name ] && touch "$D/live-$2"; shift; done ;;
  get) [ -f "$D/live-$1" ] || exit 3
       if [ -f "$D/dead" ] && [ -f "$D/prompt" ]; then echo '{"state":"finished"}'; else echo '{"state":"live","status":{"state":"idle"}}'; fi ;;
  ls) echo '{"terminals":[]}' ;;
  kill|rm) echo "$cmd $1" >> "$D/hc-calls" ;;
esac
exit 0
EOF
cat > "$B/herdr-app" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  ls) echo '{"spaces":[]}' ;;
  do) shift; echo "$*" >> "$(dirname "$0")/app-calls"; [ "$1" = space.new ] && echo '{"space":"sp1","tab":"tb1","terminal":"t9"}' ;;
esac
exit 0
EOF
printf '#!/usr/bin/env bash\n:\n' > "$B/osascript"
chmod +x "$B"/*
st() { PATH="$B:$PATH" FACTORY_ROOT="$R" env -u HC_TERMINAL_ID -u HERDR_ENV bash "$R/scripts/run-stage.sh" t "$@" 2>&1; echo "rc=$?"; }
hst() { PATH="$B:$PATH" FACTORY_ROOT="$R" HC_TERMINAL_ID=t1 env -u HERDR_ENV bash "$R/scripts/run-stage.sh" t "$@" 2>&1; echo "rc=$?"; }
rn() { PATH="$B:$PATH" FACTORY_ROOT="$R" env -u HC_TERMINAL_ID -u HERDR_ENV "$@" bash -c '. "$FACTORY_ROOT/scripts/lib.sh"; runner t'; }
ok grill-alive "$(st factory-grill grill)" "grill running still open in tab 'grill' after -1 min; wait for $R/tasks/t/work/grill.json (pr-watch.sh --file)
rc=4"
touch "$B/dead"
ok grill-dead "$(st factory-grill grill)" "grill failed no status file (timeout or worker died; open tab 'grill')
rc=2"
ok label "$(LABEL=retro st factory-debug debug)" "retro failed no status file (timeout or worker died; open tab 'retro')
rc=2"
st factory-intake intake >/dev/null
ok lean-args "$(grep -cx -e --disable-slash-commands -e "$R/worker-mcp.json" -e --strict-mcp-config "$B/start-args")" 3
ok root-skips-agents-md "$(grep -c AGENTS.md "$B/prompt")" 0
st factory-grill grill >/dev/null
ok grill-not-lean "$(grep -cx -e --disable-slash-commands "$B/start-args")" 0

# Runner follows the launching app; runner: herdr never goes headless.
ok runner-herdr-pane "$(rn HERDR_ENV=1 HC_TERMINAL_ID=t1)" herdr
ok runner-new-app "$(rn HC_TERMINAL_ID=t1)" hc
ok runner-outside "$(rn)" herdr

# hc: workers start in the task's space as tab <key>, get the prompt, and fail like herdr once dead.
rm -f "$B/dead" "$B/prompt"; echo '{"hc_space":"spT"}' > "$R/tasks/t/work/workspace.json"
ok hc-grill-alive "$(hst factory-grill grill)" "grill running still open in tab 'grill' after -1 min; wait for $R/tasks/t/work/grill.json (pr-watch.sh --file)
rc=4"
ok hc-placement "$(grep -cx -e herdr.space=spT -e factory.tab=grill -e factory.task=t -e claude "$B/hc-run-args")" 4
ok hc-prompt "$(grep -c 'KEY=grill ' "$B/prompt")" 1
ok hc-prompt-after-dashdash "$(tail -n 2 "$B/hc-run-args" | head -n 1)" --   # claude's --add-dir must not swallow it
touch "$B/dead"; rm -f "$B/prompt"
ok hc-dead "$(hst factory-intake intake)" "intake failed no status file (timeout or worker died; open tab 'intake')
rc=2"
rm -f "$B/dead" "$B/prompt"; printf 'agent_override: codex\n' >> "$R/tasks/t/factory.override.yml"
hst factory-intake intake >/dev/null
ok hc-codex-no-daemon "$(grep -cx -e --no-daemon "$B/hc-run-args")" 1

# launch-lead in the new app: a space named after the task, lead tab, default shell tab removed.
cp "$SRC/scripts/launch-lead.sh" "$R/scripts/"; rm -f "$R/tasks/t/work/workspace.json" "$B/hc-calls"
ll() { PATH="$B:$PATH" FACTORY_ROOT="$R" HC_TERMINAL_ID=t1 env -u HERDR_ENV bash "$R/scripts/launch-lead.sh" t 2>&1; }
ok hc-lead-guard "$(ll | grep -c 'still running in Herdr UI')" 1   # stub herdr reports the lead alive
touch "$B/dead"; rm -f "$B/prompt"   # herdr: lead gone; hc: lead finishes after its prompt (enough for launch)
ok hc-lead "$(ll)" "LAUNCHED space t"
ok hc-lead-space "$(jq -r .hc_space "$R/tasks/t/work/workspace.json")" sp1
ok hc-lead-shell-closed "$(grep -c -e 'kill t9' -e 'rm t9' "$B/hc-calls")" 2
us=$(FACTORY_ROOT="$R" bash "$R/scripts/run-stage.sh" t factory-debug nope 2>&1 || true)
ok unknown-stage-msg "$(grep -c "unknown stage 'nope' (valid: .*LABEL=" <<<"$us")" 1
rm -rf "$R"
finish
