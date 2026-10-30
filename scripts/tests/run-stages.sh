#!/usr/bin/env bash
# run-stages.sh: flattening, --wave/--all, and the missing-dir pre-check (no worker starts).
. "$(dirname "$0")/lib.sh"
R=$(fake_root run-stages.sh plan-meta.sh)
# shellcheck disable=SC2016
printf '#!/usr/bin/env bash\necho "$4 started"\n' > "$R/scripts/run-stage.sh"; chmod +x "$R/scripts/run-stage.sh"
mkdir -p "$R/tasks/t/a" "$R/tasks/t/b" "$R/tasks/t/c"
cat > "$R/tasks/t/plan.md" <<'EOF'
---
repos:
  - {name: a, wave: 1}
  - {name: b, wave: 2}
  - {name: c, wave: 2}
---
EOF
rs() { FACTORY_ROOT="$R" bash "$R/scripts/run-stages.sh" t factory-x execute "$@" 2>&1 | sort; }
ok one-quoted-string "$(rs "a b")" "a started
b started"
ok wave "$(rs --wave 2)" "b started
c started"
ok all "$(rs --all)" "a started
b started
c started"
ok missing-dir "$(rs "a zz")" "execute failed missing dir(s): $R/tasks/t/zz (no worker started)"
rm -rf "$R"
finish
