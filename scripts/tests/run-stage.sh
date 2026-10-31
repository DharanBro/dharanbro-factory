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
chmod +x "$B"/*
st() { PATH="$B:$PATH" FACTORY_ROOT="$R" bash "$R/scripts/run-stage.sh" t "$@" 2>&1; echo "rc=$?"; }
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
rm -rf "$R"
finish
