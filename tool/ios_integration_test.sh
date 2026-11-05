#!/usr/bin/env bash
# Runs the integration tests on the iOS simulator $UDID: every file in one
# app launch (integration_test/all_tests.dart), then
# ios_no_callkit_test.dart, which needs a process of its own. Or the files
# given. Quiet unless --loud comes first; see tool/test_defines.sh.
#
# Boots the simulator unless it is and waits until it is fully up. On CI
# ($CI set) it then stops the simulator's activity scheduler, dasd, for as
# long as it runs. Locally only with SPEAK_SIM_BOOTOUT_DASD=1, on a
# simulator made for the tests: never on anybody's own.
#
# Why: on a simulator booted for the first time dasd can deadlock (sampled
# on iOS 27.0: its own submitTaskRequest waits on a reply from itself).
# Everything that schedules a background task waits on it, axassetsd among
# them, and with it +[AVSpeechSynthesisVoice speechVoices]. Before 0.2.2
# the package asked that on the main thread, which froze the test app:
# nothing reported, and the run looked as if the tool never attached. On a
# fresh simulator that happened 3 times in 3 (it came free by itself after
# 10 to 19 minutes, or not within 27); a dasd restarted deadlocks again;
# with dasd booted out, 5 runs in 7 passed at the first attempt and the
# other 2 at the second (a different miss, see below). The voices are now
# listed off the main thread, but the tests still need them.
# tool/sim_voices.m checks that they can be listed before the tests start.
#
# Once built, an attempt that reports nothing for $IDLE_SECONDS (default
# 180; the tool's log reader sometimes misses the app's VM service address
# on a fresh simulator, and the app can take a minute to start), or has no
# result within $ATTEMPT_SECONDS (default 900), is stopped and, that being
# the simulator and not the tests, made once more after a `::warning::`.
# A test that fails is not run again here: the real-engine scenarios decide
# that themselves (test/support/scenarios.dart), and their `::warning::`
# lines are passed on to GitHub.
set -euo pipefail
# shellcheck source=tool/test_defines.sh
source "$(dirname "$0")/test_defines.sh"
cd "$(dirname "$0")/../example"
: "${UDID:?set UDID to the simulator to test on}"
limit="${ATTEMPT_SECONDS:-900}"
idle="${IDLE_SECONDS:-180}"
if [ "$#" -eq 0 ]; then
  set -- integration_test/all_tests.dart integration_test/ios_no_callkit_test.dart
fi

echo "::group::simulator $UDID"
xcrun simctl bootstatus "$UDID" -b
if [ -n "${CI:-}" ] || [ "${SPEAK_SIM_BOOTOUT_DASD:-}" = "1" ]; then
  xcrun simctl spawn "$UDID" launchctl bootout "user/$(id -u)/com.apple.dasd" || true
fi
voices="$(mktemp -d "${TMPDIR:-/tmp}/speak_voices.XXXXXX")/sim_voices"
xcrun -sdk iphonesimulator clang -fobjc-arc -mios-simulator-version-min=13.0 \
  -framework Foundation -framework AVFoundation \
  ../tool/sim_voices.m -o "$voices"
xcrun simctl spawn "$UDID" "$voices" &
query=$!
waited=0
while kill -0 "$query" 2>/dev/null && [ "$waited" -lt "${VOICES_SECONDS:-120}" ]; do
  sleep 1
  waited=$((waited + 1))
done
if kill -0 "$query" 2>/dev/null || ! wait "$query"; then
  echo "::warning::the simulator listed no speech voices within ${waited}s" \
    "(a simulator booted for the first time can take many minutes; see above)"
fi
echo "::endgroup::"

log="$(mktemp "${TMPDIR:-/tmp}/speak_test.XXXXXX")"

run_once() {
  local file="$1"
  : > "$log"
  # The app's output comes prefixed; a workflow command anywhere in a line
  # is moved to its start, where GitHub reads it.
  flutter test "$file" -d "$UDID" "${defines[@]}" \
    > >(sed -u 's/^.*\(::warning\)/\1/' | tee "$log") 2>&1 &
  local pid=$!
  local waited=0 size=0 quiet=0
  while kill -0 "$pid" 2>/dev/null; do
    sleep 5
    waited=$((waited + 5))
    # Once built, the tests report every few seconds; silence means the
    # tool never attached, or the app's main thread is blocked.
    if grep -q 'Xcode build done' "$log"; then
      local now
      now=$(wc -c < "$log")
      if [ "$now" -eq "$size" ]; then quiet=$((quiet + 5)); else quiet=0; fi
      size=$now
    fi
    local why=""
    if [ "$waited" -ge "$limit" ]; then
      why="no result after ${limit}s"
    elif [ "$quiet" -ge "$idle" ]; then
      why="nothing reported for ${idle}s since the build"
    fi
    if [ -n "$why" ]; then
      echo "::warning::$file: $why, stopping this attempt"
      pkill -P "$pid" 2>/dev/null || true
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi
  done
  wait "$pid"
}

for file in "$@"; do
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
