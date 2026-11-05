// The real-engine scenarios' trace and retry policy (support/scenarios.dart),
// over the fake engine: what is noted, and which failures are retried.
// ignore_for_file: implementation_imports
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speak/speak.dart';
import 'package:speak/src/backend/backend.dart';

import 'support/engine_trace.dart';
import 'support/fake_backend.dart';
import 'support/scenarios.dart';

void main() {
  late EngineTrace trace;
  late FakeBackend engine;
  late TracingBackend traced;

  setUp(() {
    trace = EngineTrace();
    engine = FakeBackend();
    traced = TracingBackend(engine, trace);
  });

  void say(String id, String text) =>
      traced.speak(BackendUtterance(id: id, text: text));

  test('notes the calls and reports, with the words of the ranges', () async {
    say('u1', 'One two.');
    engine
      ..start()
      ..progress(0, 3)
      ..progress(4, 7)
      ..finish();
    await traced.pause();
    await traced.dispose();
    final lines = trace.dump().split('\n');
    expect(lines.map((line) => line.substring(line.indexOf('ms') + 4)), [
      '-> speak u1 "One two."',
      '<- started u1',
      '<- range u1 0-3 "One"',
      '<- range u1 4-7 "two"',
      '<- finished u1',
      '-> pause',
      '-> dispose',
    ]);
    expect(lines.first, matches(RegExp(r'^ +\d+ ms  ')));
  });

  test('a cleared trace starts again', () {
    say('u1', 'One.');
    engine.start();
    trace.clear();
    expect(trace.dump(), '(nothing)');
    expect(trace.spoke, isFalse);
    expect(trace.engineReported, isFalse);
  });

  test('stopAll stops every backend not yet disposed', () async {
    final other = FakeBackend();
    final tracedOther = TracingBackend(other, trace);
    await tracedOther.dispose();
    await trace.stopAll();
    expect(engine.log, contains('stop'));
    expect(other.log, isNot(contains('stop')));
  });

  group('retried', () {
    test('a timeout from the core', () {
      say('u1', 'One.');
      engine.start();
      expect(
        isEnvironmental(const SpeakException(SpeakError.timeout), trace),
        isTrue,
      );
    });

    test('a scenario that waited in vain', () {
      expect(isEnvironmental(EngineStalled('the first word'), trace), isTrue);
    });

    test('any failure after text was handed over and nothing came back', () {
      say('u1', 'One.');
      expect(isEnvironmental(TestFailure('wrong'), trace), isTrue);
    });
  });

  group('word events missing only at the end', () {
    const text = 'One two three four.';

    /// Speaks [text] on the fake engine, reports [ranges] and how it ended.
    void spoken(
      List<(int, int)> ranges, {
      bool finished = true,
      String said = text,
    }) {
      say('u1', said);
      engine.start();
      for (final (start, end) in ranges) {
        engine.progress(start, end);
      }
      finished ? engine.finish() : engine.cancel();
    }

    bool retried() => isEnvironmental(TestFailure('words'), trace);

    test('the first word only, then finished: retried', () {
      spoken([(0, 3)]);
      expect(retried(), isTrue);
    });

    test('the first words in order, then finished: retried', () {
      spoken([(0, 3), (4, 7)]);
      expect(retried(), isTrue);
    });

    test('the first three words, then finished: retried', () {
      spoken([(0, 3), (4, 7), (8, 13)]);
      expect(retried(), isTrue);
    });

    test('a word with its punctuation reported apart still counts', () {
      spoken([(0, 3), (3, 4)], said: 'One, two three.');
      expect(retried(), isTrue);
    });

    test('every word reported: not retried, the answer was wrong', () {
      spoken([(0, 3), (4, 7), (8, 13), (14, 19)]);
      expect(retried(), isFalse);
    });

    test('a word skipped: not retried', () {
      spoken([(0, 3), (8, 13)]);
      expect(retried(), isFalse);
    });

    test('words out of order: not retried', () {
      spoken([(4, 7), (0, 3)]);
      expect(retried(), isFalse);
    });

    test('a word reported twice: not retried', () {
      spoken([(0, 3), (0, 3)]);
      expect(retried(), isFalse);
    });

    test('wrong offsets: not retried', () {
      spoken([(1, 3)]);
      expect(retried(), isFalse);
    });

    test('a range beyond the text: not retried', () {
      spoken([(0, 3), (30, 34)]);
      expect(retried(), isFalse);
    });

    test('not finished (cancelled): not retried', () {
      spoken([(0, 3)], finished: false);
      expect(retried(), isFalse);
    });

    test('no word at all: not retried by this rule', () {
      spoken([]);
      expect(retried(), isFalse);
    });

    test('a failure other than a test expectation: not retried', () {
      spoken([(0, 3)]);
      expect(
        isEnvironmental(
          const SpeakException(SpeakError.synthesisFailed),
          trace,
        ),
        isFalse,
      );
    });
  });

  group('not retried', () {
    test('a wrong answer from an engine that answered', () {
      say('u1', 'One two three.');
      engine
        ..start()
        ..progress(0, 3)
        ..progress(8, 14)
        ..finish();
      expect(isEnvironmental(TestFailure('words'), trace), isFalse);
    });

    test('a failure of a scenario that said nothing', () {
      expect(isEnvironmental(TestFailure('voices'), trace), isFalse);
    });

    test('an engine failure other than a timeout', () {
      say('u1', 'One.');
      engine.fail(SpeakError.synthesisFailed);
      expect(
        isEnvironmental(
          const SpeakException(SpeakError.synthesisFailed),
          trace,
        ),
        isFalse,
      );
    });

    test('an interruption counts as an answer', () {
      say('u1', 'One.');
      engine.interruptionBegins();
      expect(isEnvironmental(TestFailure('outcome'), trace), isFalse);
    });
  });

  group('runScenario', () {
    late List<String> printed;
    late int resets;
    late DebugPrintCallback saved;

    setUp(() {
      printed = [];
      resets = 0;
      saved = debugPrint;
      debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');
    });
    tearDown(() => debugPrint = saved);

    Future<void> run(Future<void> Function() body) => runScenario(
      'a scenario',
      body,
      trace,
      reset: () async => resets++,
      printPassed: false,
    );

    test('passes without a word when the body does', () async {
      await run(() async {});
      expect(printed, isEmpty);
      expect(resets, 0);
    });

    test('runs a stalled scenario once more, after a warning with the '
        'trace', () async {
      var runs = 0;
      await run(() async {
        runs++;
        say('u$runs', 'One.');
        if (runs == 1) throw EngineStalled('the first word');
      });
      expect(runs, 2);
      expect(resets, 1);
      expect(printed, hasLength(1));
      expect(
        printed.single,
        allOf(
          startsWith('::warning title=speak scenario retried::"a scenario": '),
          contains('EngineStalled'),
          contains('%0A'),
          contains('-> speak u1 "One."'),
          isNot(contains('\n')),
        ),
      );
      // The retry is traced afresh.
      expect(trace.dump(), isNot(contains('u1')));
    });

    test('fails when the retry fails too, with its trace', () async {
      await expectLater(
        run(() async {
          say('u1', 'One.');
          throw EngineStalled('the engine to start');
        }),
        throwsA(isA<EngineStalled>()),
      );
      expect(resets, 1);
      expect(printed, hasLength(2));
      expect(
        printed.last,
        startsWith('Engine trace of "a scenario", retried:'),
      );
    });

    test(
      'runs once more when only the last word events were dropped',
      () async {
        var runs = 0;
        await run(() async {
          runs++;
          say('u$runs', 'One two.');
          engine
            ..start()
            ..progress(0, 3);
          if (runs == 2) engine.progress(4, 8);
          engine.finish();
          expect(runs, 2, reason: 'the words of the first run were cut');
        });
        expect(runs, 2);
        expect(
          printed.single,
          startsWith('::warning title=speak scenario retried::'),
        );
        expect(printed.single, contains('range u1 0-3'));
      },
    );

    test('fails at once on a wrong answer, with the trace', () async {
      var runs = 0;
      await expectLater(
        run(() async {
          runs++;
          say('u1', 'One two.');
          engine
            ..start()
            ..progress(4, 7)
            ..progress(0, 3)
            ..finish();
          expect(['two', 'One'], ['One', 'two']);
        }),
        throwsA(isA<TestFailure>()),
      );
      expect(runs, 1);
      expect(resets, 0);
      expect(printed.single, startsWith('Engine trace of "a scenario":\n'));
      expect(printed.single, contains('<- range u1 4-7 "two"'));
      expect(printed.single, isNot(contains('::warning')));
    });
  });
}
