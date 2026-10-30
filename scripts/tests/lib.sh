#!/usr/bin/env bash
# Shared helpers for scripts/tests/*.sh (offline, no real clocks). Source me.
# fake_root <script...>: a throwaway factory root with factory.yml, lib.sh and the named scripts copied in.
set -uo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail=0
ok() { if [ "$2" = "$3" ]; then echo "ok   $1"; else printf 'FAIL %s\n  got:  %s\n  want: %s\n' "$1" "$2" "$3"; fail=1; fi; }
fake_root() {
  local d s; d=$(mktemp -d); mkdir -p "$d/scripts" "$d/tasks"
  cp "$SRC/factory.yml" "$d/"; cp "$SRC/scripts/lib.sh" "$d/scripts/"
  for s in "$@"; do cp "$SRC/scripts/$s" "$d/scripts/"; done
  echo "$d"
}
finish() { [ "$fail" = 0 ] && echo "PASS $(basename "$0")"; exit "$fail"; }
