import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speak/src/android/voice_list.dart';

void main() {
  group('listing the voices of an engine that has just started', () {
    test('a full list is taken at once', () {
      fakeAsync((async) {
        var asked = 0;
        List<String>? listed;
        listVoices(() {
          asked++;
          return ['en-us-x-sfg-local'];
        }, startedAt: clock.now()).then((voices) => listed = voices);
        async.flushMicrotasks();
        expect(listed, ['en-us-x-sfg-local']);
        expect(asked, 1);
      });
    });

    test('an empty or missing list is asked for again until the engine has '
        'one', () {
      fakeAsync((async) {
        final answers = <List<String>?>[
          null,
          [],
          [],
          ['en-GB'],
        ];
        var asked = 0;
        List<String>? listed;
        listVoices(
          () => answers[asked++],
          startedAt: clock.now(),
        ).then((voices) => listed = voices);
        async.elapse(const Duration(milliseconds: 599));
        expect(listed, isNull);
        async.elapse(const Duration(milliseconds: 1));
        expect(listed, ['en-GB']);
        expect(asked, 4);
      });
    });

    test('an engine with no voices is answered empty after the wait', () {
      fakeAsync((async) {
        var asked = 0;
        List<String>? listed;
        listVoices<String>(() {
          asked++;
          return [];
        }, startedAt: clock.now()).then((voices) => listed = voices);
        async.elapse(const Duration(milliseconds: 2999));
        expect(listed, isNull);
        async.elapse(const Duration(milliseconds: 1));
        expect(listed, isEmpty);
        expect(asked, 16);
      });
    });

    test('long after the start, an empty list is the answer at once', () {
      fakeAsync((async) {
        final started = clock.now();
        async.elapse(const Duration(seconds: 10));
        var asked = 0;
        List<String>? listed;
        listVoices<String>(() {
          asked++;
          return null;
        }, startedAt: started).then((voices) => listed = voices);
        async.flushMicrotasks();
        expect(listed, isEmpty);
        expect(asked, 1);
      });
    });

    test('the wait counts from the start, not from the question', () {
      fakeAsync((async) {
        final started = clock.now();
        async.elapse(const Duration(seconds: 2));
        List<String>? listed;
        listVoices<String>(
          () => [],
          startedAt: started,
        ).then((voices) => listed = voices);
        async.elapse(const Duration(milliseconds: 999));
        expect(listed, isNull);
        async.elapse(const Duration(milliseconds: 1));
        expect(listed, isEmpty);
      });
    });
  });
}
