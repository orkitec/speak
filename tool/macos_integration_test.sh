#!/usr/bin/env bash
# Runs example/integration_test on macOS, one `flutter test` per file (or the
# files given), closing the app between files: a second launch while the
# first test app is still open never attaches.
#
# The example's debug build is not sandboxed (DebugProfile.entitlements), so
# the system speech works under `flutter test`; see "Known issues" in the
# README for why a sandboxed one cannot speak when the tool starts it.
set -euo pipefail

cd "$(dirname "$0")/../example"
if [ "$#" -eq 0 ]; then set -- integration_test/*_test.dart; fi

status=0
for file in "$@"; do
  flutter test "$file" -d macos || status=1
  pkill -x speak_example 2>/dev/null || true
done
exit "$status"
