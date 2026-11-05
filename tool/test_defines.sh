# shellcheck shell=bash
# Sourced by the test scripts in tool/. Sets `defines`, the --dart-define
# flags for the real-engine tests, and drops a leading --loud from "$@".
#
# Quiet (volume 0; test/support/test_backend.dart) unless --loud is given,
# SPEAK_TEST_QUIET=0 is set, or the scripts run on CI ($CI), where nobody
# listens and the tests run at full volume. SPEAK_TEST_TRACE=1 prints the
# engine trace of every scenario, passed or not.
quiet=1
if [ -n "${CI:-}" ]; then quiet=0; fi
if [ -n "${SPEAK_TEST_QUIET:-}" ]; then quiet="$SPEAK_TEST_QUIET"; fi
if [ "${1:-}" = "--loud" ]; then quiet=0; shift; fi
defines=("--dart-define=SPEAK_TEST_QUIET=$quiet")
if [ "${SPEAK_TEST_TRACE:-}" = "1" ]; then
  defines+=("--dart-define=SPEAK_TEST_TRACE=1")
fi
if [ "$quiet" = "1" ]; then
  echo "speak tests: quiet (volume 0); --loud for full volume"
else
  echo "speak tests: full volume"
fi
