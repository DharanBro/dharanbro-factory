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
rm -rf "$R"; finish
