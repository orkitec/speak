#!/usr/bin/env bash
# Runs each integration test file on the iOS simulator $UDID, one `flutter
# test` per file. On a GitHub macOS runner the tool sometimes never attaches
# to the freshly launched app and waits forever; an attempt that is not done
# within $ATTEMPT_SECONDS (default 480) is killed and tried once more.
set -euo pipefail
cd "$(dirname "$0")/../example"
: "${UDID:?set UDID to the simulator to test on}"
limit="${ATTEMPT_SECONDS:-480}"

run_once() {
  local file="$1"
  flutter test "$file" -d "$UDID" &
  local pid=$!
  local waited=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge "$limit" ]; then
      echo "::warning::$file: no result after ${limit}s, stopping this attempt"
      pkill -P "$pid" 2>/dev/null || true
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 5
    waited=$((waited + 5))
  done
  wait "$pid"
}

for file in integration_test/*_test.dart; do
  echo "::group::$file"
  status=0
  run_once "$file" || status=$?
  if [ "$status" -eq 124 ]; then
    run_once "$file"
  elif [ "$status" -ne 0 ]; then
    exit "$status"
  fi
  echo "::endgroup::"
done
