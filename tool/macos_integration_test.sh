#!/usr/bin/env bash
# Runs example/integration_test on macOS.
#
# `flutter test -d macos` starts the app as a child of the flutter tool, and
# there AVSpeechSynthesizer cannot load its speech audio unit (OSStatus -3000,
# invalidComponentID): every utterance is cancelled at once. Started through
# LaunchServices, as any user starts it, speech works. So the test app is
# built, opened with `open`, and its output read until the run ends.
set -euo pipefail

cd "$(dirname "$0")/../example"
test_file="${1:-integration_test/speak_test.dart}"
app="build/macos/Build/Products/Debug/speak_example.app"
log="$(mktemp -t speak_macos_it)"

flutter build macos --debug -t "$test_file"
open -n --stdout "$log" --stderr "$log" "$app"

status=1
for _ in $(seq 1 300); do
  sleep 2
  if grep -q 'All tests passed!' "$log"; then status=0; break; fi
  if grep -q 'Some tests failed' "$log"; then break; fi
done

cat "$log"
# The app stays open after the run; close the copy this script started.
pid="$(pgrep -n -f "$app/Contents/MacOS/speak_example" || true)"
if [ -n "$pid" ]; then kill "$pid"; fi
if [ "$status" -ne 0 ]; then echo 'macOS integration tests failed (or timed out).' >&2; fi
exit "$status"
