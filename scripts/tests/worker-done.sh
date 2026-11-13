#!/usr/bin/env bash
# worker-done.sh refuses `done` when a repo's pushed head (@{u}) has no matching push-gate record, accepts it with one.
. "$(dirname "$0")/lib.sh"
R=$(fake_root worker-done.sh); T="$R/tasks/t"; mkdir -p "$T/work"
git init -q --bare "$R/remote.git"
git clone -q "$R/remote.git" "$T/r" 2>/dev/null; cd "$T/r" || exit 1
git -c user.email=a@b -c user.name=a commit -q --allow-empty -m c && git push -q -u origin HEAD 2>/dev/null
status() { jq -r .status "$T/work/k.json"; }
bash "$R/scripts/worker-done.sh" t k done "all good" >/dev/null; ok no-gate-record-fails "$(status)" failed
ok summary-keeps-worker-text "$(jq -r .summary "$T/work/k.json" | grep -c 'all good')" 1
git rev-parse HEAD > "$T/work/push-gate-r.ok"
bash "$R/scripts/worker-done.sh" t k done "all good" >/dev/null; ok matching-record-passes "$(status)" done
git -c user.email=a@b -c user.name=a commit -q --allow-empty -m c2 && git push -q 2>/dev/null
bash "$R/scripts/worker-done.sh" t k done "all good" >/dev/null; ok stale-record-after-new-push-fails "$(status)" failed
bash "$R/scripts/worker-done.sh" t k blocked "stuck" >/dev/null; ok blocked-not-gated "$(status)" blocked
finish
