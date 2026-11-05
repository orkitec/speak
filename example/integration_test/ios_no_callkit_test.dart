// With IosSpeakOptions(callKit: false), CallKit is never loaded, for apps
// sold on the China storefront. A file of its own, because a process cannot
// unload a framework once loaded; ios_callkit_test.dart checks the opposite.
// ignore_for_file: implementation_imports
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:objective_c/objective_c.dart' as objc;
import 'package:speak/speak.dart';
import 'package:speak/src/darwin/darwin_backend.dart';

import '../../test/support/test_backend.dart';

bool _classLoaded(String name) {
  try {
    objc.getClass(name);
    return true;
  } on objc.FailedToLoadClassException {
    return false;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  useTestBackend();

  testWidgets('without CallKit, the package never loads it', (_) async {
    if (kIsWeb || !Platform.isIOS) return markTestSkipped('iOS only');
    // Not linked, so not loaded at start, unless the system loaded it before
    // the test began (some simulator runtimes do, at launch). Then nothing
    // can be said about the package from here; the build check
    // (tool/check_no_callkit.sh) still proves it is not linked.
    final loadedAtStart = _classLoaded('CXCallObserver');
    if (loadedAtStart) debugPrint('CallKit was loaded at launch already');

    final backend = DarwinBackend(callKit: false);
    addTearDown(backend.dispose);
    expect(await backend.isInCall(), isFalse);
    await backend.activateAudio(SpeakAudio.navigation);
    await backend.deactivateAudio();
    final speak = Speak(ios: const IosSpeakOptions(callKit: false))
      ..language = 'en';
    addTearDown(speak.dispose);
    await speak.voices();
    // An utterance asks about calls first; one in a language no voice speaks
    // goes no further, so the speaker's own path asks without speaking.
    await expectLater(
      speak('Hallo.', language: 'xx-XX'),
      throwsA(isA<SpeakException>()),
    );
    // Asked about calls, claimed and gave back the session, listed voices:
    // CallKit is still not loaded.
    if (!loadedAtStart) expect(_classLoaded('CXCallObserver'), isFalse);

    // Speaking works as before. (Once it speaks, iOS's own speech synthesis
    // loads CallKit into the process: Apple's framework, not the app's
    // binary, which is what App Review checks; so nothing is asserted about
    // it afterwards.)
    expect(await speak('Turn left.'), SpeakOutcome.completed);
  });
}
