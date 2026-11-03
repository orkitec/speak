#!/usr/bin/env bash
# Runs the browser tests (test/web_test.dart and the platform-independent
# tests) in Chrome. speechSynthesis refuses to speak before a user gesture
# ("not-allowed"); Chrome started with this flag lets the tests speak.
set -euo pipefail

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
CHROME_EXECUTABLE="$wrapper" flutter test --platform chrome "$@"
