import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speak/src/android/voice_list.dart';

/// A voice name; installed unless it ends in `?`.
bool _installed(String voice) => !voice.endsWith('?');

void main() {
  group('listing the voices of an engine that has just started', () {
    /// Lists from [answers], one per look (the last one repeated), and
    /// returns what was listed and when, and how often it looked.
    (List<String>?, Duration?, int) run(
      FakeAsync async,
      List<List<String>?> answers, {
      Duration startedBefore = Duration.zero,
      Duration wait = const Duration(seconds: 30),
    }) {
      final started = clock.now();
      async.elapse(startedBefore);
      final asked = clock.now();
      var looks = 0;
      List<String>? listed;
      Duration? after;
      listVoices(
        () =>
            answers[looks++ < answers.length ? looks - 1 : answers.length - 1],
        startedAt: started,
        installed: _installed,
      ).then((voices) {
        listed = voices;
        after = clock.now().difference(asked);
      });
      async.elapse(wait);
      return (listed, after, looks);
    }

    test('a full list is taken once a second look agrees', () {
      fakeAsync((async) {
        final (listed, after, looks) = run(async, [
          ['en-us-x-sfg-local'],
        ]);
        expect(listed, ['en-us-x-sfg-local']);
        expect(after, const Duration(milliseconds: 200));
        expect(looks, 2);
      });
    });

    test('an empty or missing list is looked at again until the engine has '
        'one', () {
      fakeAsync((async) {
        final (listed, after, _) = run(async, [
          null,
          [],
          [],
          ['en-GB'],
        ]);
        expect(listed, ['en-GB']);
        expect(after, const Duration(milliseconds: 800));
      });
    });

    test('a list with no voice installed yet is looked at again', () {
      fakeAsync((async) {
        final (listed, after, _) = run(async, [
          ['en-GB?', 'de-DE?'],
          ['en-GB?', 'de-DE?'],
          ['en-GB', 'de-DE?'],
        ]);
        expect(listed, ['en-GB', 'de-DE?']);
        expect(after, const Duration(milliseconds: 600));
      });
    });

    test('a list still filling in is taken once it holds', () {
      fakeAsync((async) {
        final (listed, after, _) = run(async, [
          ['en-GB'],
          ['en-GB', 'en-US'],
          ['en-GB', 'en-US', 'de-DE'],
          ['en-GB', 'en-US', 'de-DE'],
        ]);
        expect(listed, ['en-GB', 'en-US', 'de-DE']);
        expect(after, const Duration(milliseconds: 600));
      });
    });

    test('an engine with no voices is answered empty after the wait', () {
      fakeAsync((async) {
        final (listed, after, looks) = run(async, [[]]);
        expect(listed, isEmpty);
        expect(after, voicesSettle);
        expect(
          looks,
          voicesSettle.inMilliseconds ~/ voicesPoll.inMilliseconds + 1,
        );
      });
    });

    test('an engine with no voice installed is answered as it is after the '
        'wait', () {
      fakeAsync((async) {
        final (listed, after, _) = run(async, [
          ['en-GB?'],
        ]);
        expect(listed, ['en-GB?']);
        expect(after, voicesSettle);
      });
    });

    test('long after the start, the list is taken at once', () {
      fakeAsync((async) {
        final (listed, after, looks) = run(async, [
          null,
          ['en-GB'],
        ], startedBefore: voicesSettle + const Duration(seconds: 1));
        expect(listed, isEmpty);
        expect(after, Duration.zero);
        expect(looks, 1);
      });
    });

    test('the wait counts from the start, not from the question', () {
      fakeAsync((async) {
        final (listed, after, _) = run(async, [
          [],
        ], startedBefore: const Duration(seconds: 2));
        expect(listed, isEmpty);
        expect(after, voicesSettle - const Duration(seconds: 2));
      });
    });
  });

  test('the engine is given ten seconds to load its voices', () {
    // Measured on CI, the first full list after the engine started: API 31
    // 213 and 621 ms, API 34 942 and 1432 ms; Velorki's API 35 emulators,
    // three to a runner, more than 3 s (a later speaker, seconds on, had
    // it). Ten seconds is three times the window that was too short, and
    // only the first listing of a speaker can wait that long.
    expect(voicesSettle, const Duration(seconds: 10));
  });

  group('whether the engine may still be loading its voices', () {
    test('within the ten seconds after its start, yes', () {
      fakeAsync((async) {
        final started = clock.now();
        async.elapse(voicesSettle - const Duration(milliseconds: 1));
        expect(voicesLoading(started), isTrue);
      });
    });

    test('after them, no', () {
      fakeAsync((async) {
        final started = clock.now();
        async.elapse(voicesSettle);
        expect(voicesLoading(started), isFalse);
      });
    });
  });
}
