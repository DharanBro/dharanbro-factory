#!/usr/bin/env bash
# chrome-path.sh   print the Chrome for Testing binary path (installs it once if missing)
find_cft() {
  ls -d "$HOME"/.cache/chrome-for-testing/chrome/*/chrome-mac-*/"Google Chrome for Testing.app"/Contents/MacOS/"Google Chrome for Testing" 2>/dev/null | tail -1
}
p=$(find_cft || true)
if [ -z "$p" ]; then
  npx --yes puppeteer browsers install chrome@stable --path "$HOME/.cache/chrome-for-testing" >&2
  p=$(find_cft || true)
fi
[ -n "$p" ] || { echo "Chrome for Testing not found" >&2; exit 1; }
echo "$p"
