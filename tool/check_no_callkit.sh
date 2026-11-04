#!/usr/bin/env bash
# Fails if the package's iOS glue links CallKit or refers to any of its
# symbols: App Review rejects apps containing CallKit on the China storefront,
# so the package only ever loads it at run time (IosSpeakOptions.callKit).
#
#   tool/check_no_callkit.sh <path to speak_darwin.framework/speak_darwin>...
set -euo pipefail

status=0
for binary in "$@"; do
  if otool -L "$binary" | grep -q CallKit; then
    echo "::error::$binary links CallKit"
    status=1
  fi
  if nm -u "$binary" | grep -qE '_OBJC_CLASS_\$_CX|CallKit'; then
    echo "::error::$binary refers to CallKit symbols"
    nm -u "$binary" | grep -E '_OBJC_CLASS_\$_CX|CallKit'
    status=1
  fi
  [ "$status" -eq 0 ] && echo "$binary: no CallKit"
done
exit "$status"
