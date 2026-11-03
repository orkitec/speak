#!/usr/bin/env bash
# Regenerates the platform bindings:
#   lib/src/darwin/av_bindings.dart and darwin/av_bindings.m (ffigen; Xcode)
#   lib/src/android/jni_bindings.dart (jnigen; a JDK 17-21 and
#   ANDROID_SDK_ROOT with the Android 36 platform)
# Pass "darwin" or "android" to regenerate one of them.
set -euo pipefail

cd "$(dirname "$0")/.."
which="${1:-all}"
if [ "$which" = all ] || [ "$which" = darwin ]; then
  dart run tool/ffigen.dart
fi
if [ "$which" = all ] || [ "$which" = android ]; then
  dart run tool/jnigen.dart
fi
dart format lib/src/darwin/av_bindings.dart lib/src/android/jni_bindings.dart
