// The platform code the test app can drive itself: CallKit's call check and
// the session notifications on iOS, audio focus and the audio mode on
// Android. The backends are used directly where the core would hide what is
// checked. See support/take_audio.dart.
// ignore_for_file: implementation_imports
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:speak/speak.dart';
import 'package:speak/src/android/android_backend.dart';
import 'package:speak/src/android/jni_bindings.dart' as android;
import 'package:speak/src/backend/backend.dart';
import 'package:objective_c/objective_c.dart';
import 'package:speak/src/darwin/av_bindings.dart';
import 'package:speak/src/darwin/darwin_backend.dart';

import 'support/take_audio.dart';
import '../../test/support/engine_trace.dart';
import '../../test/support/test_backend.dart';

const _long =
    'This is a long sentence, long enough to still be speaking when another '
    'app asks for the audio in the middle of it, and then some more words.';

bool get _ios => !kIsWeb && Platform.isIOS;
bool get _android => !kIsWeb && Platform.isAndroid;

/// Speaks [text] and waits until the engine reports it started (the audio
/// is claimed by then), and a moment more. Not until the first word: a
/// simulator under load can render a whole utterance before it reports any
/// word, and then reports every word and the end at once.
Future<Future<SpeakOutcome>> _speaking(
  Speak speak,
  String text,
  EngineTrace trace,
) async {
  final said = speak(text);
  final started = DateTime.now();
  while (!trace.engineStarted &&
      DateTime.now().difference(started) < const Duration(seconds: 8)) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  await Future<void>.delayed(const Duration(milliseconds: 500));
  return said;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  useTestBackend();
  final trace = traceEveryTest();

  // The folder ends in the normal audio mode, whatever a test did.
  tearDownAll(() async {
    if (_android) {
      await leaveCallMode();
      expect(await audioMode(), android.AudioManager.MODE_NORMAL);
    }
  });

  group('iOS and macOS', () {
    tracedTestWidgets(
      'the voices listed off the main thread are the system\'s',
      trace,
      (_) async {
        if (kIsWeb || !(Platform.isIOS || Platform.isMacOS)) {
          return markTestSkipped('iOS and macOS only');
        }
        final backend = DarwinBackend();
        addTearDown(backend.dispose);
        // The system's list on this thread, of the voices it can hand out
        // by identifier, as the backend lists them.
        List<String> direct() => [
          for (final object in AVSpeechSynthesisVoice.speechVoices().asDart())
            if (AVSpeechSynthesisVoice.voiceWithIdentifier(
                  AVSpeechSynthesisVoice.as(object).identifier,
                ) !=
                null)
              AVSpeechSynthesisVoice.as(object).identifier.toDartString(),
        ];
        // The system's own order is not stable between two listings, and on
        // a fresh GitHub runner voices are still being added for a while:
        // the same voices, once the list has settled.
        var listed = <String>{};
        var system = <String>{};
        for (var i = 0; i < 10; i++) {
          listed = {for (final voice in await backend.voices()) voice.id};
          system = direct().toSet();
          if (listed.length == system.length && listed.containsAll(system)) {
            break;
          }
          debugPrint(
            'voices differ: only off the main thread '
            '${listed.difference(system)}, only on it '
            '${system.difference(listed)}',
          );
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        expect(listed, system);
        expect(listed, isNotEmpty);
      },
    );
  });

  group('iOS', () {
    tracedTestWidgets(
      'isInCall asks CallKit and says no call on the simulator',
      trace,
      (_) async {
        if (!_ios) return markTestSkipped('iOS only');
        final backend = DarwinBackend();
        addTearDown(backend.dispose);
        expect(await backend.isInCall(), isFalse);
      },
    );

    tracedTestWidgets(
      'the session given back after the linger is no interruption',
      trace,
      (_) async {
        if (!_ios) return markTestSkipped('iOS only');
        final listener = DarwinBackend();
        addTearDown(listener.dispose);
        final events = <BackendInterruption>[];
        final heard = listener.interruptions.listen(events.add);
        addTearDown(heard.cancel);

        final speak = Speak(
          audio: const SpeakAudio(linger: Duration(milliseconds: 300)),
        )..language = 'en';
        addTearDown(speak.dispose);
        expect(await speak('Turn left.'), SpeakOutcome.completed);
        // Past the linger: the session is deactivated (and on iOS 27 that
        // posts DidBecomeInactive, without an interruption context).
        await Future<void>.delayed(const Duration(seconds: 2));
        expect(events, isEmpty);
      },
    );

    tracedTestWidgets(
      'an interruption is reported once, and nothing after dispose',
      trace,
      (_) async {
        if (!_ios) return markTestSkipped('iOS only');
        final backend = DarwinBackend();
        final events = <BackendInterruption>[];
        final heard = backend.interruptions.listen(events.add);
        postInterruption(began: true);
        await Future<void>.delayed(const Duration(milliseconds: 500));
        postInterruption(began: false);
        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect(events, [BackendInterruption.began, BackendInterruption.ended]);

        await backend.dispose();
        // Observers removed: a notification now reaches nothing (and does not
        // crash on a closed stream).
        postInterruption(began: true);
        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect(events, hasLength(2));
        await heard.cancel();
      },
    );
  });

  group('Android', () {
    tracedTestWidgets(
      'a permanent loss cuts the utterance; the next one is spoken',
      trace,
      (_) async {
        if (!_android) return markTestSkipped('Android only');
        final speak = Speak()..language = 'en';
        addTearDown(speak.dispose);
        final said = await _speaking(speak, _long, trace);
        final music = requestFocus(android.AudioManager.AUDIOFOCUS_GAIN);
        addTearDown(() => abandonFocus(music));
        expect(
          await said.timeout(const Duration(seconds: 5)),
          SpeakOutcome.interrupted,
        );
        // Nothing is held up after a permanent loss: the next one asks for the
        // focus again and gets it.
        expect(await speak('Turn left.'), SpeakOutcome.completed);
      },
    );

    tracedTestWidgets(
      'a short sound that may duck us does not cut the utterance',
      trace,
      (_) async {
        if (!_android) return markTestSkipped('Android only');
        final speak = Speak()..language = 'en';
        addTearDown(speak.dispose);
        final said = await _speaking(
          speak,
          'One two three four five six.',
          trace,
        );
        final chime = requestFocus(
          android.AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK,
        );
        addTearDown(() => abandonFocus(chime));
        expect(await said, SpeakOutcome.completed);
      },
    );

    tracedTestWidgets(
      'after a transient loss and the focus back, the focus is given '
      'up: the app underneath gets it back',
      trace,
      (_) async {
        if (!_android) return markTestSkipped('Android only');
        // Music playing underneath, which pauses rather than ducks, so it hears
        // every change.
        final changes = <int>[];
        final music = requestFocus(
          android.AudioManager.AUDIOFOCUS_GAIN,
          pauseWhenDucked: true,
          onChange: changes.add,
        );
        addTearDown(() => abandonFocus(music));

        final speak = Speak(
          audio: const SpeakAudio(linger: Duration(seconds: 30)),
        )..language = 'en';
        addTearDown(speak.dispose);
        final said = await _speaking(speak, _long, trace);

        // A call rings: the speaker loses the focus for now.
        final call = requestFocus(
          android.AudioManager.AUDIOFOCUS_GAIN_TRANSIENT,
        );
        addTearDown(() => abandonFocus(call));
        expect(
          await said.timeout(const Duration(seconds: 5)),
          SpeakOutcome.interrupted,
        );
        changes.clear();
        // The call ends: the focus goes back to the speaker, which gives it up
        // at once (not after its 30 s linger), so the music gets it.
        abandonFocus(call);
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (!changes.contains(android.AudioManager.AUDIOFOCUS_GAIN) &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(changes, contains(android.AudioManager.AUDIOFOCUS_GAIN));
      },
    );

    tracedTestWidgets('isInCall follows the audio mode', trace, (_) async {
      if (!_android) return markTestSkipped('Android only');
      final backend = AndroidBackend(const AndroidSpeakOptions());
      addTearDown(backend.dispose);
      expect(await backend.isInCall(), isFalse);
      // Registered first, so the mode is put back even if entering it fails.
      addTearDown(leaveCallMode);
      await enterCallMode();
      expect(await backend.isInCall(), isTrue);
      await leaveCallMode();
      expect(await backend.isInCall(), isFalse);
    });
  });
}
