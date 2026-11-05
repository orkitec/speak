#!/usr/bin/env bash
# Runs example/integration_test on the Android emulator $DEVICE (default
# emulator-5554). The scenarios' `::warning::` lines (the app's output comes
# prefixed) are moved to the start of their line, where GitHub reads them.
# Quiet unless --loud comes first; see tool/test_defines.sh.
set -euo pipefail
# shellcheck source=tool/test_defines.sh
source "$(dirname "$0")/test_defines.sh"
cd "$(dirname "$0")/../example"
flutter test integration_test -d "${DEVICE:-emulator-5554}" "${defines[@]}" "$@" 2>&1 \
  | sed -u 's/^.*\(::warning\)/\1/'
