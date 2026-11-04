#!/usr/bin/env bash
# init.sh links the system's herdr-core into bin/ with hc beside it, and herdr-app from HERDR_APP_BIN; a re-run relinks.
. "$(dirname "$0")/lib.sh"
R=$(fake_root init.sh); S="$R/sys"; mkdir -p "$S"
printf '#!/bin/sh\necho "hc 9.9.9"\n' > "$S/herdr-core"; printf '#!/bin/sh\necho "herdr-app 1.0"\n' > "$S/app"; chmod +x "$S"/*
run_init() { PATH="$S:$(dirname "$(command -v bash)"):/usr/bin:/bin" HOME="$R" HERDR_APP_BIN="$S/app" FACTORY_ROOT="$R" bash "$R/scripts/init.sh" 2>&1; }
out=$(run_init)
ok core-linked "$(readlink "$R/bin/herdr-core")" "$S/herdr-core"
ok hc-beside "$(readlink "$R/bin/hc")" herdr-core
ok app-linked "$(readlink "$R/bin/herdr-app")" "$S/app"
ok report "$out" "hc         hc 9.9.9 (linked to $S/herdr-core)
herdr-app  herdr-app 1.0 (linked to $S/app)"
ok rerun "$(run_init)" "$out"
rm -rf "$R"
finish
