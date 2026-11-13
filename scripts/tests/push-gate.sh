#!/usr/bin/env bash
# push-gate.sh CodeRabbit part: repo off -> skipped; on + record for HEAD -> pass; stale sha / no record / unresolved finding -> fail.
. "$(dirname "$0")/lib.sh"
R=$(fake_root push-gate.sh cr-enabled.sh); T="$R/tasks/t"; A="$T/artifacts"; mkdir -p "$A"
git init -q --bare "$R/remote.git"; git clone -q "$R/remote.git" "$T/r" 2>/dev/null
g() { git -C "$T/r" -c user.email=a@b -c user.name=a "$@"; }
g checkout -q -b main; g commit -q --allow-empty -m c; g push -q -u origin main 2>/dev/null
g checkout -q -b feat; g commit -q --allow-empty -m f
gate() { FACTORY_ROOT="$R" bash "$R/scripts/push-gate.sh" t r >/dev/null 2>&1; echo $?; }
rec() { printf '# coderabbit review: r\nhead: %s\nresult: %s\n## findings\n%s\n' "$(g rev-parse HEAD)" "$1" "${2:-}" > "$A/cr-review-r.md"; }
printf 'repos:\n  r: {branch: main, coderabbit: false}\n' > "$R/repos.yml"
ok disabled-skipped "$(gate)" 0
printf 'repos:\n  r: {branch: main, coderabbit: true}\n' > "$R/repos.yml"
ok enabled-no-record-fails "$(gate)" 1
rec clean "- a.ts | bug | fixed in abc1234"; ok enabled-record-for-head-passes "$(gate)" 0
g commit -q --allow-empty -m next; ok enabled-stale-sha-fails "$(gate)" 1
rec clean "- a.ts | bug | unresolved"; ok unresolved-finding-fails "$(gate)" 1
rec clean "- a.ts | bug | answered a.ts:4"; ok answered-without-answers-entry-fails "$(gate)" 1
echo "- a.ts | bug-key-8 | handled at a.ts:4" > "$A/push-gate-answers-r.md"; ok answered-with-entry-passes "$(gate)" 0
rec dirty; ok result-not-clean-fails "$(gate)" 1

# helpers resolve next to the script, not under FACTORY_ROOT/scripts; scan failure and cr-enabled error must not pass silently
P=$(fake_root push-gate.sh cr-enabled.sh sonar-scan.sh); E=$(mktemp -d); mkdir -p "$E/scripts" "$E/tasks/t/artifacts"; cp "$SRC/factory.yml" "$E/"
git clone -q "$R/remote.git" "$E/tasks/t/r" 2>/dev/null; git -C "$E/tasks/t/r" fetch -q origin; git -C "$E/tasks/t/r" checkout -q -b feat origin/main 2>/dev/null; git -C "$E/tasks/t/r" -c user.email=a@b -c user.name=a commit -q --allow-empty -m f
gate2() { FACTORY_ROOT="$E" bash "$P/scripts/push-gate.sh" t r >/dev/null 2>&1; echo $?; }
printf 'repos:\n  r: {branch: main, coderabbit: true}\n' > "$E/repos.yml"
ok helpers-from-script-dir-not-root "$(gate2)" 1   # real cr-enabled sees coderabbit:true, no record -> fail (was: skipped, pass)
printf 'repos:\n  r: {branch: main, coderabbit: false, sonar: {project_key: k}}\n' > "$E/repos.yml"
printf '#!/usr/bin/env bash\nexit 1\n' > "$P/scripts/sonar-scan.sh"
echo '**PASS** stale' > "$E/tasks/t/artifacts/push-gate-r.md"
ok sonar-scan-fail-exits-1 "$(gate2)" 1
ok sonar-scan-fail-writes-fail-report "$(grep -c 'FAIL' "$E/tasks/t/artifacts/push-gate-r.md")" 1
printf 'repos:\n  r: {branch: main, coderabbit: true}\n' > "$E/repos.yml"
printf '#!/usr/bin/env bash\nexit 3\n' > "$P/scripts/cr-enabled.sh"
ok cr-enabled-error-fails "$(gate2)" 1
ok cr-enabled-error-unverified "$(grep -c 'UNVERIFIED: cr-enabled' "$E/tasks/t/artifacts/push-gate-r.md")" 1
rm -rf "$R" "$P" "$E"; finish
