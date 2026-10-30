#!/usr/bin/env bash
# ci-run.sh against a local bare "origin": a failure that also happens on origin/main is PRE-EXISTING (not counted),
# one the branch caused is FAIL, install runs in the base worktree, and that worktree is removed afterwards.
. "$(dirname "$0")/lib.sh"
R=$(fake_root ci-run.sh)
g() { git -c user.name=t -c user.email=t@t "$@" >/dev/null 2>&1; }
cat > "$R/repos.yml" <<'EOF'
repos:
  r:
    branch: main
    install: touch installed
    ci_checks:
      - exit 3
      - test -f feature.txt
      - test ! -f feature.txt
      - test -f installed || exit 5
EOF
git init -q --bare -b main "$R/origin.git"
g clone "$R/origin.git" "$R/repos/r"; g -C "$R/repos/r" commit --allow-empty -m init; g -C "$R/repos/r" push origin HEAD:main
g -C "$R/repos/r" worktree add -b feat "$R/tasks/t/r" origin/main
touch "$R/tasks/t/r/feature.txt"; g -C "$R/tasks/t/r" add feature.txt; g -C "$R/tasks/t/r" commit -m feat
mkdir -p "$R/tasks/t/artifacts"
ok run "$(FACTORY_ROOT="$R" bash "$R/scripts/ci-run.sh" t r 2>&1; echo "rc=$?")" "PRE-EXISTING(3) exit 3
PASS test -f feature.txt
FAIL(1) test ! -f feature.txt
FAIL(5) test -f installed || exit 5
rc=1"
ok json "$(jq -c . "$R/tasks/t/artifacts/ci-preexisting-r.json")" '[{"cmd":"exit 3","rc":3}]'
ok md-base-rc "$(grep -c 'origin/main: rc 0' "$R/tasks/t/artifacts/ci-runs-r.md")" 2
ok base-worktree-removed "$(git -C "$R/repos/r" worktree list | wc -l | tr -d ' ')" 2
rm -rf "$R"
finish
