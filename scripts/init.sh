#!/usr/bin/env bash
# init.sh   One-time setup (README "Setup"): put herdr-core (`hc`) and the new Herdr app's window CLI (`herdr-app`)
# in bin/ (gitignored; lib.sh puts bin/ first on PATH). A system herdr-core is linked; without one, the official
# installer puts it in bin/. Safe to re-run: it relinks, and keeps a copy it installed earlier (`hc update` updates it).
. "$(dirname "$0")/lib.sh"
B="$ROOT/bin"; mkdir -p "$B"
sys_path=$(tr ':' '\n' <<<"$PATH" | grep -vxF "$B" | paste -sd: -)   # PATH without bin/: where the system's copies are

core=$(PATH="$sys_path" command -v herdr-core || true)
if [ -z "$core" ] && [ -x "$HOME/.local/bin/herdr-core" ]; then core="$HOME/.local/bin/herdr-core"; fi   # installer default, maybe off PATH
if [ -n "$core" ]; then
  ln -sfn "$core" "$B/herdr-core"; how="linked to $core"
elif [ -f "$B/herdr-core" ] && [ ! -L "$B/herdr-core" ]; then
  how="installed in bin/ earlier; update with hc update"
else
  rm -f "$B/herdr-core"   # a link whose system copy is gone
  curl -fsSL https://releases.herdr.dev/core/install.sh | HC_INSTALL_DIR="$B" sh
  how="installed into bin/"
fi
ln -sfn herdr-core "$B/hc"
echo "hc         $("$B/hc" --version) ($how)"

# The window CLI: on PATH, else the macOS app bundle. Only the new app (dev.herdr.app) answers --version with "herdr-app".
app=${HERDR_APP_BIN:-$(PATH="$sys_path" command -v herdr-app || true)}
if [ -z "$app" ]; then
  while IFS= read -r a; do
    if "$a/Contents/MacOS/Herdr" --version 2>/dev/null | grep -q '^herdr-app '; then app="$a/Contents/MacOS/Herdr"; break; fi
  done < <(mdfind "kMDItemCFBundleIdentifier == 'dev.herdr.app'" 2>/dev/null || true)
fi
if [ -n "$app" ]; then
  ln -sfn "$app" "$B/herdr-app"; echo "herdr-app  $("$B/herdr-app" --version) (linked to $app)"
else
  echo "herdr-app  not found: install the new Herdr app and re-run (only the hc runner needs it; HERDR_APP_BIN=<path> picks one)"
fi
