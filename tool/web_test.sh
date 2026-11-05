#!/usr/bin/env bash
# Runs the browser tests (test/web_test.dart and the platform-independent
# tests) in Chrome. speechSynthesis refuses to speak before a user gesture
# ("not-allowed"); Chrome started with this flag lets the tests speak.
# Quiet unless --loud comes first; see tool/test_defines.sh.
set -euo pipefail
# shellcheck source=tool/test_defines.sh
source "$(dirname "$0")/test_defines.sh"

cd "$(dirname "$0")/.."
chrome="${CHROME:-}"
if [ -z "$chrome" ]; then
  for candidate in \
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    "$(command -v google-chrome || true)" \
    "$(command -v google-chrome-stable || true)" \
    "$(command -v chromium || true)"; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then chrome="$candidate"; break; fi
  done
fi
# A template with X's: GNU mktemp (the Linux runner) refuses a bare prefix.
dir="$(mktemp -d "${TMPDIR:-/tmp}/speak_chrome.XXXXXX")"
wrapper="$dir/chrome.sh"
printf '#!/usr/bin/env bash\nexec "%s" --autoplay-policy=no-user-gesture-required "$@"\n' "$chrome" > "$wrapper"
chmod +x "$wrapper"
# The scenarios' `::warning::` lines (test/support/scenarios.dart) are moved
# to the start of their line, where GitHub reads them.
CHROME_EXECUTABLE="$wrapper" flutter test --platform chrome "${defines[@]}" "$@" 2>&1 \
  | sed -u 's/^.*\(::warning\)/\1/'
