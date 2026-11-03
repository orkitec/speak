// The real-engine scenarios, shared by example/integration_test (iOS, macOS,
// Android) and test/web_test.dart (Chrome), so every platform is held to the
// same behaviour.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speak/speak.dart';

const _long =
    'This is a long sentence, long enough to be cut off, paused and '
    'resumed before it reaches its end, so that every test has time.';

bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Defines every scenario through [scenario]: `testWidgets` on a device,
/// `test` in the browser.
void speakScenarios(
  void Function(String description, Future<void> Function() body) scenario,
) {
  late Speak speak;
  late String language;

  setUpAll(() async {
    final probe = Speak();
    final voices = await probe.voices();
    await probe.dispose();
    // English where there is any; the first installed voice's language
    // otherwise (a bare emulator image may have one language only).
    language = voices.any((v) => v.language.startsWith('en') && v.isInstalled)
        ? 'en'
        : voices.firstWhere((v) => v.isInstalled).language;
  });

  setUp(() => speak = Speak()..language = language);
  tearDown(() => speak.dispose());

  /// Waits until [condition] holds, failing after [within].
  Future<void> until(
    bool Function() condition, {
    Duration within = const Duration(seconds: 15),
  }) async {
    final deadline = DateTime.now().add(within);
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) fail('timed out waiting');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  scenario('the platform is supported', () async {
    expect(Speak.isSupported, isTrue);
  });

  scenario('lists voices with normalised languages', () async {
    final voices = await speak.voices();
    expect(voices, isNotEmpty);
    for (final voice in voices) {
      expect(voice.id, isNotEmpty);
      expect(voice.language, matches(RegExp(r'^[a-z]{2,3}(-[A-Za-z0-9]+)*$')));
    }
    final english = await speak.voices(language: language);
    expect(english, isNotEmpty);
    expect(english.every((v) => v.language.startsWith(language)), isTrue);
  });

  scenario('tells which languages can be spoken', () async {
    // The browser's own voices synthesise online.
    expect(
      await speak.availability(language),
      kIsWeb
          ? isIn([VoiceAvailability.available, VoiceAvailability.needsNetwork])
          : VoiceAvailability.available,
    );
    expect(await speak.availability('xx-XX'), VoiceAvailability.unsupported);
  });

  scenario('speaks and completes', () async {
    final watch = Stopwatch()..start();
    expect(await speak('Turn left.'), SpeakOutcome.completed);
    // Said, not dropped: it took the engine some time.
    expect(watch.elapsedMilliseconds, greaterThan(300));
  });

  scenario('speaks in a chosen voice', () async {
    final voice = (await speak.voices(language: language)).first;
    expect(await speak('Hello.', voice: voice), SpeakOutcome.completed);
  });

  scenario('fails for a language no voice speaks', () async {
    await expectLater(
      speak('Hallo.', language: 'xx-XX'),
      throwsA(
        isA<SpeakException>().having(
          (e) => e.error,
          'error',
          SpeakError.languageUnavailable,
        ),
      ),
    );
  });

  scenario('reports word progress', () async {
    final words = <String>[];
    final outcome = await speak(
      'One two three four.',
      onProgress: (p) => words.add(p.word),
    );
    expect(outcome, SpeakOutcome.completed);
    if (words.isEmpty && (_android || kIsWeb)) {
      // Word ranges are optional: Android engines need not call
      // onRangeStart, and a browser's voice need not send `boundary` events
      // (Chrome on Linux sends none). Where they are reported, they are
      // checked strictly below; iOS and macOS always report them.
      markTestSkipped(
        'this ${kIsWeb ? 'browser voice' : 'engine'} reports no word ranges',
      );
      return;
    }
    expect(words, containsAllInOrder(['One', 'two', 'three']));
  });

  scenario('stop interrupts what is being said', () async {
    final said = speak(_long);
    await until(() => speak.isSpeaking);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await speak.stop();
    expect(await said, SpeakOutcome.interrupted);
  });

  scenario('an interrupting utterance cuts in', () async {
    final first = speak(_long);
    final queued = speak('Never said.');
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final urgent = speak('Turn now.', queue: SpeakQueue.interrupt);
    expect(await first, SpeakOutcome.interrupted);
    expect(await queued, SpeakOutcome.interrupted);
    expect(await urgent, SpeakOutcome.completed);
  });

  scenario('queued utterances are said in order', () async {
    final order = <String>[];
    await Future.wait([
      speak('First.').then((_) => order.add('first')),
      speak('Second.').then((_) => order.add('second')),
    ]);
    expect(order, ['first', 'second']);
  });

  scenario('pauses and resumes', () async {
    final words = <String>[];
    final said = speak(
      'One two three four five six seven eight nine ten.',
      onProgress: (p) => words.add(p.word),
    );
    // Paused once the engine is really speaking: after the first word where
    // words are reported, else a moment after it started. A slow simulator
    // can take seconds to start.
    await until(() => speak.isSpeaking, within: const Duration(seconds: 30));
    final started = DateTime.now();
    await until(
      () =>
          words.isNotEmpty ||
          DateTime.now().difference(started) > const Duration(seconds: 2),
      within: const Duration(seconds: 30),
    );
    await speak.pause();
    expect(speak.isPaused, isTrue);
    final heard = words.length;
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    // Nothing more is spoken while paused (a word in flight may finish).
    expect(words.length, lessThanOrEqualTo(heard + 1));
    await speak.resume();
    expect(await said, SpeakOutcome.completed);
  });

  scenario('drops an utterance that waited too long', () async {
    final first = speak(_long);
    final stale = speak('Stale.', expireAfter: const Duration(seconds: 1));
    expect(await stale, SpeakOutcome.expired);
    await speak.stop();
    await first;
  });

  scenario('holds and releases the audio around utterances', () async {
    final held = Speak(audio: SpeakAudio.navigation)..language = language;
    await held.holdAudio();
    expect(await held('One.'), SpeakOutcome.completed);
    expect(await held('Two.'), SpeakOutcome.completed);
    await held.releaseAudio();
    await held.dispose();
  });

  scenario('leads in, then lingers', () async {
    final leading = Speak(
      audio: const SpeakAudio(
        leadIn: Duration(seconds: 1),
        linger: Duration(seconds: 3),
      ),
    )..language = language;
    final watch = Stopwatch()..start();
    expect(await leading('One.'), SpeakOutcome.completed);
    final first = watch.elapsed;
    if (!kIsWeb) {
      // The silence is spoken by the engine: the utterance takes at least
      // that long. The web has no lead-in.
      expect(first, greaterThanOrEqualTo(const Duration(seconds: 1)));
    }
    // Within the linger: the claim is reused, and there is no lead-in.
    watch.reset();
    expect(await leading('One.'), SpeakOutcome.completed);
    if (!kIsWeb) expect(watch.elapsed, lessThan(first));
    await leading.dispose();
  });

  scenario('every audio mode speaks', () async {
    for (final audio in const [
      SpeakAudio.prompt,
      SpeakAudio.navigation,
      SpeakAudio.plain,
      SpeakAudio.exclusive,
      SpeakAudio(otherAudio: OtherAudio.pauseSpoken),
      SpeakAudio(otherAudio: OtherAudio.duckAndPauseSpoken),
    ]) {
      final mode = Speak(audio: audio)..language = language;
      expect(await mode('Okay.'), SpeakOutcome.completed, reason: '$audio');
      await mode.dispose();
    }
  });

  scenario('lists Android engines, the default first', () async {
    final engines = await Speak.androidEngines();
    if (!_android) {
      expect(engines, isEmpty);
      return;
    }
    expect(engines, isNotEmpty);
    expect(engines.first.isDefault, isTrue);
    final chosen = Speak(
      android: AndroidSpeakOptions(engine: engines.first.name),
    )..language = language;
    expect(await chosen('Engine.'), SpeakOutcome.completed);
    await chosen.dispose();
  });
}
