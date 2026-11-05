// Interruptions on the real engine: the audio taken away mid-utterance,
// utterances while it is gone, and speaking again after. iOS and Android;
// see support/take_audio.dart for how the test plays a call.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:speak/speak.dart';

import 'support/take_audio.dart';
// ignore: implementation_imports
import 'package:speak/src/android/jni_bindings.dart' as android;
import '../../test/support/test_backend.dart';

const _long =
    'This is a long sentence, long enough to still be speaking when the '
    'audio is taken away from it by a call that rings in the middle.';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  useTestBackend();

  bool supported() => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  // Whatever a test did to the audio mode, the folder ends in the normal
  // one: a device left in call mode would carry it into other runs.
  tearDownAll(() async {
    if (!kIsWeb && Platform.isAndroid) {
      await leaveCallMode();
      expect(await audioMode(), android.AudioManager.MODE_NORMAL);
    }
  });

  late Speak speak;
  setUp(() => speak = Speak()..language = 'en');
  tearDown(() => speak.dispose());

  testWidgets('an interruption ends what is being said, blocks only while '
      'the audio is still taken, and lets the next one speak after', (_) async {
    if (!supported()) {
      markTestSkipped('needs iOS or Android');
      return;
    }
    var words = 0;
    final cut = speak(_long, onProgress: (_) => words++);
    // Taken once the engine is really speaking (the audio is claimed by
    // then): after the first word, or a moment after starting where words
    // are not reported.
    final started = DateTime.now();
    while (words == 0 &&
        DateTime.now().difference(started) < const Duration(seconds: 8)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    // Given back however the test ends.
    addTearDown(giveAudioBack);
    await takeAudio();
    expect(
      await cut.timeout(const Duration(seconds: 5)),
      SpeakOutcome.interrupted,
    );

    if (Platform.isAndroid) {
      // The focus is still with the other app: positive evidence, blocked.
      expect(await speak('Never said.'), SpeakOutcome.blocked);
    } else {
      // iOS: the test can post an interruption but not start a call, so
      // there is no call for CallKit to see and the session can be claimed.
      // A remembered interruption alone must not block: this utterance is
      // spoken. (iOS does not promise an end for every beginning.)
      expect(await speak('Spoken anyway.'), SpeakOutcome.completed);
    }

    await giveAudioBack();
    final watch = Stopwatch()..start();
    expect(await speak('Turn left.'), SpeakOutcome.completed);
    // Said, not dropped.
    expect(watch.elapsed, greaterThan(const Duration(milliseconds: 300)));
  });

  testWidgets('in a call (Android), utterances are blocked unless asked to '
      'speak anyway', (_) async {
    if (kIsWeb || !Platform.isAndroid) {
      markTestSkipped('Android only: iOS has no call state to ask');
      return;
    }
    // Registered first, so the mode is put back even if entering it fails.
    addTearDown(leaveCallMode);
    await enterCallMode();
    expect(await speak('Turn left.'), SpeakOutcome.blocked);

    final anyway = Speak(
      audio: const SpeakAudio(duringCalls: SpeakDuringCalls.speak),
    )..language = 'en';
    addTearDown(anyway.dispose);
    expect(await anyway('Turn left.'), SpeakOutcome.completed);

    await leaveCallMode();
    expect(await speak('Turn right.'), SpeakOutcome.completed);
  });
}
