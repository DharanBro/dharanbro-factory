#!/usr/bin/env bash
# ui-login.sh <url>   open a VISIBLE Chrome for Testing on the factory's own profile so you can log in
# (Auth0 etc). Close the window when done; headless UI tests then reuse the saved session.
set -euo pipefail
ROOT="${FACTORY_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
url="${1:?url}"
mkdir -p "$ROOT/.browser-profile"
exec "$("$ROOT/scripts/chrome-path.sh")" --user-data-dir="$ROOT/.browser-profile" "$url"
