# Contributing

Contributions are accepted under the BSD-3-Clause licence the package is published under (inbound = outbound); no CLA, no sign-off.

- Run `dart format .`, `flutter analyze` and `flutter test` before opening a
  pull request; `tool/web_test.sh` for anything that touches the web.
- Behaviour changes in the core (`lib/src/speak.dart`) come with a test in
  `test/speak_test.dart` against the fake engine; platform behaviour with a
  scenario in `test/support/scenarios.dart`.
- The bindings in `lib/src/darwin/av_bindings.dart`,
  `darwin/av_bindings.m` and `lib/src/android/jni_bindings.dart` are
  generated: change `tool/ffigen.dart` or `tool/jnigen.dart` and run
  `tool/generate.sh`.
