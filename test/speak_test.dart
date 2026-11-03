import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speak/speak.dart';
import 'package:speak/src/backend/unsupported_backend.dart';
import 'package:speak/src/speak.dart' show backendFactoryOverride, timeoutFor;

import 'support/fake_backend.dart';

/// Lets every pending microtask and zero-length timer run.
Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late FakeBackend engine;
  late Speak speak;

  Speak create({
    SpeakAudio audio = SpeakAudio.prompt,
    bool canPause = true,
    StopReply stopReply = StopReply.cancel,
    List<Voice>? voices,
  }) {
    engine = FakeBackend(
      canPause: canPause,
      stopReply: stopReply,
      voices: voices,
    );
    backendFactoryOverride = (_) => engine;
    return speak = Speak(audio: audio);
  }

  tearDown(() => backendFactoryOverride = null);

  group('speaking', () {
    setUp(create);

    test('completes when the engine says it finished', () async {
      final said = speak('Turn left.');
      await settle();
      expect(engine.spoken.single.text, 'Turn left.');
      engine
        ..start()
        ..finish();
      expect(await said, SpeakOutcome.completed);
    });

    test('says nothing for an empty text', () async {
      expect(await speak(''), SpeakOutcome.completed);
      expect(engine.log, isEmpty);
    });

    test('hands the engine one utterance at a time', () async {
      final first = speak('One.');
      final second = speak('Two.');
      await settle();
      expect(engine.spoken.map((u) => u.text), ['One.']);
      engine.finish();
      expect(await first, SpeakOutcome.completed);
      await settle();
      expect(engine.spoken.map((u) => u.text), ['One.', 'Two.']);
      engine.finish();
      expect(await second, SpeakOutcome.completed);
    });

    test('gives every utterance its own id', () async {
      unawaited(speak('One.'));
      await settle();
      engine.finish();
      unawaited(speak('Two.'));
      await settle();
      expect(engine.spoken[0].id, isNot(engine.spoken[1].id));
    });

    test('passes rate, pitch and volume, the call over the defaults', () async {
      speak
        ..rate = 1.2
        ..volume = 0.5;
      unawaited(speak('A.', pitch: 1.5));
      await settle();
      final u = engine.spoken.single;
      expect((u.rate, u.pitch, u.volume), (1.2, 1.5, 0.5));
    });

    test('keeps its defaults', () {
      speak
        ..pitch = 1.5
        ..volume = 0.25
        ..rate = 2;
      expect((speak.rate, speak.pitch, speak.volume), (2.0, 1.5, 0.25));
    });

    test('a failing progress listener does not stop the utterance', () async {
      final errors = <Object>[];
      await runZonedGuarded(() async {
        final said = speak(
          'Hi there.',
          onProgress: (_) => throw StateError('x'),
        );
        await settle();
        engine
          ..progress(0, 2)
          ..finish();
        expect(await said, SpeakOutcome.completed);
      }, (error, _) => errors.add(error));
      expect(errors.single, isA<StateError>());
    });

    test('rejects a rate, pitch or volume out of range', () {
      expect(() => speak('A.', rate: 0), throwsArgumentError);
      expect(() => speak('A.', volume: 1.5), throwsArgumentError);
      expect(() => speak('A.', pitch: 3), throwsArgumentError);
      expect(() => speak.rate = -1, throwsArgumentError);
    });

    test('a cancel nobody asked for is a failure', () async {
      final said = speak('A.');
      await settle();
      engine.cancel();
      await expectLater(
        said,
        throwsA(
          isA<SpeakException>().having(
            (e) => e.error,
            'error',
            SpeakError.synthesisFailed,
          ),
        ),
      );
    });

    test(
      'an engine failure fails that utterance and the queue goes on',
      () async {
        final first = speak('A.');
        final second = speak('B.');
        await settle();
        engine.fail(SpeakError.notAllowed);
        await expectLater(
          first,
          throwsA(
            isA<SpeakException>().having(
              (e) => e.error,
              'error',
              SpeakError.notAllowed,
            ),
          ),
        );
        await settle();
        expect(engine.spoken.last.text, 'B.');
        engine.finish();
        expect(await second, SpeakOutcome.completed);
      },
    );

    test('an engine failure after a stop is an interruption', () async {
      engine.stopReply = StopReply.silent;
      final said = speak('A.');
      await settle();
      final stopping = speak.stop();
      engine.fail(SpeakError.synthesisFailed, engine.spoken.single.id);
      await stopping;
      expect(await said, SpeakOutcome.interrupted);
    });

    test('an engine that throws fails that utterance only', () async {
      engine.speakError = StateError('no engine');
      final first = speak('A.');
      await expectLater(first, throwsA(isA<SpeakException>()));
      engine.speakError = null;
      final second = speak('B.');
      await settle();
      engine.finish();
      expect(await second, SpeakOutcome.completed);
    });

    test('ignores events about utterances it is not speaking', () async {
      final said = speak('A.');
      await settle();
      engine.finish('someone-else');
      await settle();
      var done = false;
      unawaited(said.then((_) => done = true));
      await settle();
      expect(done, isFalse);
      engine.finish();
      expect(await said, SpeakOutcome.completed);
    });
  });

  group('interrupting', () {
    test('stop cuts off the current utterance and drops the queue', () async {
      create();
      final first = speak('One.');
      final second = speak('Two.');
      await settle();
      await speak.stop();
      expect(await first, SpeakOutcome.interrupted);
      expect(await second, SpeakOutcome.interrupted);
      expect(engine.spoken.map((u) => u.text), ['One.']);
      expect(engine.log, contains('stop'));
    });

    test(
      'decides "interrupted" itself, even when the engine says finished',
      () async {
        create(stopReply: StopReply.finish);
        final said = speak('One.');
        await settle();
        await speak.stop();
        expect(await said, SpeakOutcome.interrupted);
      },
    );

    test('stop does not wait forever for an engine that never answers', () {
      fakeAsync((async) {
        create(stopReply: StopReply.silent);
        SpeakOutcome? outcome;
        var stopped = false;
        speak('One.').then((o) => outcome = o);
        async.flushMicrotasks();
        speak.stop().then((_) => stopped = true);
        async.elapse(const Duration(seconds: 2));
        expect(outcome, SpeakOutcome.interrupted);
        expect(stopped, isTrue);
      });
    });

    test('stop while idle completes at once', () async {
      create();
      await speak.stop();
      expect(engine.log, isNot(contains('speak')));
    });

    test('an interrupting utterance cuts in and is spoken next', () async {
      create();
      final first = speak('In two hundred metres, turn left.');
      final queued = speak('Then right.');
      await settle();
      final urgent = speak('Turn left now.', queue: SpeakQueue.interrupt);
      expect(await first, SpeakOutcome.interrupted);
      expect(await queued, SpeakOutcome.interrupted);
      await settle();
      expect(engine.spoken.map((u) => u.text), [
        'In two hundred metres, turn left.',
        'Turn left now.',
      ]);
      engine.finish();
      expect(await urgent, SpeakOutcome.completed);
    });

    test('an interrupting utterance when idle is just spoken', () async {
      create();
      final said = speak('Now.', queue: SpeakQueue.interrupt);
      await settle();
      expect(engine.log, isNot(contains('stop')));
      engine.finish();
      expect(await said, SpeakOutcome.completed);
    });
  });

  group('safeguards', () {
    test('an engine that never finishes times out, scaled to the text', () {
      fakeAsync((async) {
        create(stopReply: StopReply.silent);
        Object? shortError;
        Object? longError;
        speak('Hi.').catchError((Object e) {
          shortError = e;
          return SpeakOutcome.completed;
        });
        async.elapse(const Duration(seconds: 11));
        expect(
          shortError,
          isA<SpeakException>().having(
            (e) => e.error,
            'error',
            SpeakError.timeout,
          ),
        );
        expect(engine.log, contains('stop'));

        speak('word ' * 200).catchError((Object e) {
          longError = e;
          return SpeakOutcome.completed;
        });
        async.elapse(const Duration(seconds: 30));
        expect(longError, isNull);
        async.elapse(const Duration(minutes: 5));
        expect(longError, isA<SpeakException>());
      });
    });

    test('a slower rate gets more time', () {
      fakeAsync((async) {
        create();
        Object? error;
        final text = 'word ' * 40;
        speak(text, rate: 0.5).catchError((Object e) {
          error = e;
          return SpeakOutcome.completed;
        });
        async.elapse(timeoutFor(text, 1) + const Duration(seconds: 1));
        expect(error, isNull);
        async.elapse(timeoutFor(text, 0.5));
        expect(error, isA<SpeakException>());
      });
    });

    test('the queue moves on after a timeout', () {
      fakeAsync((async) {
        create(stopReply: StopReply.silent);
        speak('Stuck.').catchError((_) => SpeakOutcome.completed);
        SpeakOutcome? next;
        speak('Next.').then((o) => next = o);
        async.elapse(const Duration(seconds: 11));
        expect(engine.spoken.last.text, 'Next.');
        engine.finish();
        async.flushMicrotasks();
        expect(next, SpeakOutcome.completed);
      });
    });

    test('an utterance still waiting when expireAfter runs out is dropped', () {
      fakeAsync((async) {
        create();
        speak('Long one.');
        SpeakOutcome? stale;
        speak(
          'In 200 metres.',
          expireAfter: const Duration(seconds: 6),
        ).then((o) => stale = o);
        async.elapse(const Duration(seconds: 7));
        expect(stale, SpeakOutcome.expired);
        engine.finish();
        async.flushMicrotasks();
        expect(engine.spoken.map((u) => u.text), ['Long one.']);
      });
    });

    test('expireAfter does not cut off an utterance that has started', () {
      fakeAsync((async) {
        create();
        SpeakOutcome? outcome;
        speak(
          'A.',
          expireAfter: const Duration(seconds: 1),
        ).then((o) => outcome = o);
        async.elapse(const Duration(seconds: 3));
        expect(outcome, isNull);
        engine.finish();
        async.flushMicrotasks();
        expect(outcome, SpeakOutcome.completed);
      });
    });
  });

  group('audio', () {
    test(
      'is claimed before the first utterance and given back after the last',
      () async {
        create(audio: SpeakAudio.navigation);
        final first = speak('One.');
        final second = speak('Two.');
        await settle();
        expect(engine.log, ['activate:duck', 'speak:One.']);
        engine.finish();
        await first;
        await settle();
        engine.finish();
        await second;
        await settle();
        expect(engine.log, [
          'activate:duck',
          'speak:One.',
          'speak:Two.',
          'deactivate',
        ]);
      },
    );

    test('is given back after a stop', () async {
      create();
      unawaited(speak('One.'));
      await settle();
      await speak.stop();
      await settle();
      expect(engine.log.last, 'deactivate');
    });

    test('a failed claim does not keep the text from being spoken', () async {
      create();
      engine.activateError = StateError('session busy');
      final said = speak('One.');
      await settle();
      engine.finish();
      expect(await said, SpeakOutcome.completed);
    });

    test(
      'held, it is claimed at once and stays claimed until released',
      () async {
        create();
        await speak.holdAudio();
        expect(engine.log, ['activate:duck']);
        unawaited(speak('One.'));
        await settle();
        engine.finish();
        await settle();
        unawaited(speak('Two.'));
        await settle();
        engine.finish();
        await settle();
        expect(engine.log.where((l) => l.startsWith('activate')), hasLength(1));
        expect(engine.log, isNot(contains('deactivate')));
        await speak.releaseAudio();
        expect(engine.log.last, 'deactivate');
      },
    );

    test(
      'released while speaking, it is given back after the utterance',
      () async {
        create();
        await speak.holdAudio();
        unawaited(speak('One.'));
        await settle();
        await speak.releaseAudio();
        expect(engine.log, isNot(contains('deactivate')));
        engine.finish();
        await settle();
        expect(engine.log.last, 'deactivate');
      },
    );

    test('releasing audio that was never held does nothing', () async {
      create();
      await speak.releaseAudio();
      expect(engine.log, isEmpty);
    });

    test('released when idle, it is given back at once', () async {
      create();
      await speak.holdAudio();
      await speak.releaseAudio();
      expect(engine.log, ['activate:duck', 'deactivate']);
    });
  });

  group('voices', () {
    final voices = [
      fakeVoice('us', 'en-US'),
      fakeVoice('gb', 'en-GB', quality: VoiceQuality.enhanced),
      fakeVoice('de', 'de_DE'),
      fakeVoice('fr-missing', 'fr-FR', installed: false),
    ];

    test('lists them, best first, filtered by language', () async {
      create(voices: voices);
      expect((await speak.voices()).map((v) => v.id), [
        'gb',
        'de',
        'us',
        'fr-missing',
      ]);
      expect((await speak.voices(language: 'en')).map((v) => v.id), [
        'gb',
        'us',
      ]);
    });

    test('a language picks the best voice for it', () async {
      create(voices: voices);
      unawaited(speak('Hallo.', language: 'de-de'));
      await settle();
      expect(engine.spoken.single.voiceId, 'de');
      expect(engine.spoken.single.language, 'de-DE');
    });

    test('a voice is used as it is', () async {
      create(voices: voices);
      unawaited(speak('Hello.', voice: voices[0]));
      await settle();
      expect(engine.spoken.single.voiceId, 'us');
    });

    test(
      'the call overrides the defaults, and a language a default voice',
      () async {
        create(voices: voices);
        speak.voice = voices[0];
        unawaited(speak('Hallo.', language: 'de'));
        await settle();
        expect(engine.spoken.single.voiceId, 'de');
        engine.finish();
        speak.language = 'en-GB';
        speak.voice = null;
        unawaited(speak('Hello.'));
        await settle();
        expect(engine.spoken.last.voiceId, 'gb');
      },
    );

    test('a language no voice speaks fails', () async {
      create(voices: voices);
      await expectLater(
        speak('Ciao.', language: 'it-IT'),
        throwsA(
          isA<SpeakException>().having(
            (e) => e.error,
            'error',
            SpeakError.languageUnavailable,
          ),
        ),
      );
      expect(engine.spoken, isEmpty);
    });

    test('a voice that is not installed fails', () async {
      create(voices: voices);
      await expectLater(
        speak('Bonjour.', voice: voices[3]),
        throwsA(
          isA<SpeakException>().having(
            (e) => e.error,
            'error',
            SpeakError.voiceUnavailable,
          ),
        ),
      );
    });

    test('an engine that lists no voices gets the language as it is', () async {
      create();
      unawaited(speak('Hola.', language: 'es_ES'));
      await settle();
      expect(engine.spoken.single.voiceId, isNull);
      expect(engine.spoken.single.language, 'es-ES');
    });

    test(
      'asks the engine for its voices once, until voices() is called',
      () async {
        create(voices: voices);
        unawaited(speak('A.', language: 'en'));
        await settle();
        engine.finish();
        unawaited(speak('B.', language: 'en'));
        await settle();
        expect(engine.voiceCalls, 1);
        engine.installed = [...voices, fakeVoice('it', 'it-IT')];
        await speak.voices();
        engine.finish();
        unawaited(speak('C.', language: 'it'));
        await settle();
        expect(engine.spoken.last.voiceId, 'it');
      },
    );

    test('availability goes by the voices', () async {
      create(voices: voices);
      expect(await speak.availability('en-AU'), VoiceAvailability.available);
      expect(await speak.availability('fr'), VoiceAvailability.notInstalled);
      expect(await speak.availability('ja'), VoiceAvailability.unsupported);
    });

    test('availability takes the engine\'s word when it has one', () async {
      create(voices: voices);
      engine.languageHint = VoiceAvailability.notInstalled;
      expect(await speak.availability('it'), VoiceAvailability.notInstalled);
      engine.languageHint = null;
      expect(await speak.availability('it'), VoiceAvailability.unsupported);
    });
  });

  group('progress', () {
    setUp(create);

    test('reports the range being spoken', () async {
      final ranges = <SpeechProgress>[];
      unawaited(speak('Turn left now.', onProgress: ranges.add));
      await settle();
      engine
        ..progress(0, 4)
        ..progress(5, 9);
      expect(ranges.map((r) => r.word), ['Turn', 'left']);
      expect(ranges.first, const SpeechProgress('Turn left now.', 0, 4));
    });

    test(
      'finds the end of the word when the engine only gives the start',
      () async {
        final ranges = <SpeechProgress>[];
        unawaited(speak('Turn left now.', onProgress: ranges.add));
        await settle();
        engine
          ..progress(5, 5)
          ..progress(10, 0);
        expect(ranges.map((r) => r.word), ['left', 'now.']);
      },
    );

    test('clamps ranges past the end of the text', () async {
      final ranges = <SpeechProgress>[];
      unawaited(speak('Hi.', onProgress: ranges.add));
      await settle();
      engine.progress(0, 99);
      expect(ranges.single.word, 'Hi.');
    });
  });

  group('pausing, natively', () {
    setUp(create);

    test('pauses and resumes the engine', () async {
      final said = speak('A long sentence.');
      await settle();
      await speak.pause();
      expect(speak.isPaused, isTrue);
      expect(engine.log, contains('pause'));
      await speak.resume();
      expect(speak.isPaused, isFalse);
      expect(engine.log, contains('resume'));
      engine.finish();
      expect(await said, SpeakOutcome.completed);
    });

    test('gives the audio back while paused', () async {
      unawaited(speak('A long sentence.'));
      await settle();
      await speak.pause();
      expect(engine.log.last, 'deactivate');
      await speak.resume();
      expect(engine.log.sublist(engine.log.length - 2), [
        'activate:duck',
        'resume',
      ]);
    });

    test('holds the queue while paused, also for new utterances', () async {
      await speak.pause();
      final said = speak('Waiting.');
      await settle();
      expect(engine.spoken, isEmpty);
      await speak.resume();
      await settle();
      expect(engine.spoken.single.text, 'Waiting.');
      engine.finish();
      expect(await said, SpeakOutcome.completed);
    });

    test('does not time out while paused', () {
      fakeAsync((async) {
        // Created inside the fake zone, so its futures run on fake time.
        create();
        Object? error;
        speak('A.').catchError((Object e) {
          error = e;
          return SpeakOutcome.completed;
        });
        async.flushMicrotasks();
        speak.pause();
        async.elapse(const Duration(minutes: 10));
        expect(error, isNull);
        speak.resume();
        async.elapse(const Duration(seconds: 30));
        expect(error, isA<SpeakException>());
      });
    });

    test('counts only the time spent speaking towards the timeout', () {
      fakeAsync((async) {
        create();
        Object? error;
        SpeakOutcome? outcome;
        // 'A.' may take timeoutFor('A.', 1), about 10.3 s.
        final allowed = timeoutFor('A.', 1);
        speak(
          'A.',
        ).then<void>((o) => outcome = o, onError: (Object e) => error = e);
        async.elapse(const Duration(seconds: 5));
        speak.pause();
        // Paused far longer than the whole timeout.
        async.elapse(const Duration(minutes: 10));
        expect(error, isNull);
        speak.resume();
        // What is left is the allowance minus the 5 s already spoken.
        async.elapse(allowed - const Duration(seconds: 6));
        expect(error, isNull);
        async.elapse(const Duration(seconds: 2));
        expect(
          error,
          isA<SpeakException>().having(
            (e) => e.error,
            'error',
            SpeakError.timeout,
          ),
        );
        expect(outcome, isNull);
      });
    });

    test('paused longer than the timeout, it still completes', () {
      fakeAsync((async) {
        create();
        Object? error;
        SpeakOutcome? outcome;
        speak(
          'A.',
        ).then<void>((o) => outcome = o, onError: (Object e) => error = e);
        async.elapse(const Duration(seconds: 2));
        speak.pause();
        async.elapse(const Duration(minutes: 10));
        speak.resume();
        async.elapse(const Duration(seconds: 2));
        engine.finish();
        async.flushMicrotasks();
        expect(error, isNull);
        expect(outcome, SpeakOutcome.completed);
      });
    });

    test('stop while paused interrupts and unpauses', () async {
      final said = speak('A.');
      await settle();
      await speak.pause();
      await speak.stop();
      expect(await said, SpeakOutcome.interrupted);
      expect(speak.isPaused, isFalse);
    });

    test('an interrupting utterance resumes a paused speaker', () async {
      final first = speak('A.');
      await settle();
      await speak.pause();
      final urgent = speak('Now!', queue: SpeakQueue.interrupt);
      expect(await first, SpeakOutcome.interrupted);
      await settle();
      expect(speak.isPaused, isFalse);
      expect(engine.spoken.last.text, 'Now!');
      engine.finish();
      expect(await urgent, SpeakOutcome.completed);
    });
  });

  group('pausing, where the engine cannot', () {
    setUp(() => create(canPause: false));

    test('stops, and resumes from the last word reported', () async {
      final ranges = <SpeechProgress>[];
      const text = 'In two hundred metres, turn left.';
      final said = speak(text, onProgress: ranges.add);
      await settle();
      engine
        ..progress(0, 2)
        ..progress(3, 6);
      await speak.pause();
      expect(engine.log, contains('stop'));
      expect(engine.log, isNot(contains('pause')));
      await settle();
      var done = false;
      unawaited(said.then((_) => done = true));
      await settle();
      expect(done, isFalse, reason: 'the stop for a pause ends nothing');

      await speak.resume();
      await settle();
      expect(engine.spoken.last.text, 'two hundred metres, turn left.');
      // Offsets from the engine are about the remainder; the caller hears
      // about the whole text.
      engine.progress(4, 11);
      expect(ranges.last, const SpeechProgress(text, 7, 14));
      expect(ranges.last.word, 'hundred');
      engine.finish();
      expect(await said, SpeakOutcome.completed);
    });

    test('resumes from the start when no word was reported', () async {
      final said = speak('No ranges here.');
      await settle();
      await speak.pause();
      await speak.resume();
      await settle();
      expect(engine.spoken.map((u) => u.text), [
        'No ranges here.',
        'No ranges here.',
      ]);
      engine.finish();
      expect(await said, SpeakOutcome.completed);
    });

    test('pausing twice resumes from the word reported last', () async {
      const text = 'one two three four';
      final said = speak(text);
      await settle();
      engine.progress(4, 7);
      await speak.pause();
      await speak.resume();
      await settle();
      expect(engine.spoken.last.text, 'two three four');
      engine.progress(4, 9);
      await speak.pause();
      await speak.resume();
      await settle();
      expect(engine.spoken.last.text, 'three four');
      engine.finish();
      expect(await said, SpeakOutcome.completed);
    });

    test('stop while paused interrupts without waiting on the engine', () {
      fakeAsync((async) {
        SpeakOutcome? outcome;
        speak('A.').then((o) => outcome = o);
        async.flushMicrotasks();
        speak.pause();
        async.flushMicrotasks();
        speak.stop();
        async.flushMicrotasks();
        expect(outcome, SpeakOutcome.interrupted);
      });
    });
  });

  group('lifecycle', () {
    test('an unsupported platform throws UnsupportedError', () async {
      backendFactoryOverride = (_) => const UnsupportedBackend();
      final speak = Speak();
      expect(() => speak('Hello.'), throwsUnsupportedError);
      expect(speak.voices, throwsUnsupportedError);
      expect(() => speak.availability('en'), throwsUnsupportedError);
      await speak.stop();
      await speak.dispose();
    });

    test('dispose interrupts everything and releases the engine', () async {
      create();
      final first = speak('One.');
      final second = speak('Two.');
      await settle();
      await speak.dispose();
      expect(await first, SpeakOutcome.interrupted);
      expect(await second, SpeakOutcome.interrupted);
      expect(engine.log.last, 'dispose');
      expect(() => speak('Three.'), throwsStateError);
    });

    test('isSpeaking follows the utterance', () async {
      create();
      expect(speak.isSpeaking, isFalse);
      final said = speak('A.');
      await settle();
      expect(speak.isSpeaking, isTrue);
      engine.finish();
      await said;
      expect(speak.isSpeaking, isFalse);
    });
  });
}
