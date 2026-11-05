#!/usr/bin/env bash
# Runs example/integration_test on macOS: every file in one app launch
# (integration_test/all_tests.dart; the files only iOS runs apart skip here
# anyway), or one `flutter test` per file given, closing the app between
# them: a second launch while the first test app is still open never
# attaches. The scenarios' `::warning::` lines are passed on to GitHub.
# Quiet unless --loud comes first; see tool/test_defines.sh.
#
# The example's debug build is not sandboxed (DebugProfile.entitlements), so
# the system speech works under `flutter test`; see "Known issues" in the
# README for why a sandboxed one cannot speak when the tool starts it.
set -euo pipefail
# shellcheck source=tool/test_defines.sh
source "$(dirname "$0")/test_defines.sh"

cd "$(dirname "$0")/../example"
if [ "$#" -eq 0 ]; then set -- integration_test/all_tests.dart; fi

status=0
for file in "$@"; do
  # The app's output comes prefixed ("flutter: "); a workflow command
  # anywhere in a line is moved to its start, where GitHub reads it.
  flutter test "$file" -d macos "${defines[@]}" 2>&1 | sed -u 's/^.*\(::warning\)/\1/' || status=1
  pkill -x speak_example 2>/dev/null || true
done
exit "$status"
