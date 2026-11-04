import 'package:flutter_test/flutter_test.dart';
import 'package:speak/speak.dart';
import 'package:speak/src/speak.dart' show backendFactoryOverride;

import 'support/fake_backend.dart';

void main() {
  tearDown(() => backendFactoryOverride = null);

  test('CallKit is asked by default', () {
    expect(const IosSpeakOptions().callKit, isTrue);
  });

  test('the options are values', () {
    expect(
      const IosSpeakOptions(callKit: false),
      const IosSpeakOptions(callKit: false),
    );
    expect(
      const IosSpeakOptions(),
      isNot(const IosSpeakOptions(callKit: false)),
    );
    expect(
      const IosSpeakOptions(callKit: false).hashCode,
      const IosSpeakOptions(callKit: false).hashCode,
    );
  });

  test('the options reach the backend, the default when none are given', () {
    final seen = <IosSpeakOptions>[];
    backendFactoryOverride = (android, ios) {
      seen.add(ios);
      return FakeBackend();
    };
    Speak();
    Speak(ios: const IosSpeakOptions(callKit: false));
    expect(seen, [
      const IosSpeakOptions(),
      const IosSpeakOptions(callKit: false),
    ]);
  });

  test('the Android options still reach the backend beside them', () {
    AndroidSpeakOptions? seen;
    backendFactoryOverride = (android, ios) {
      seen = android;
      return FakeBackend();
    };
    Speak(android: const AndroidSpeakOptions(engine: 'e'));
    expect(seen, const AndroidSpeakOptions(engine: 'e'));
  });
}
