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

  group('not retried', () {
    test('a wrong answer from an engine that answered', () {
      say('u1', 'One two three.');
      engine
        ..start()
        ..progress(0, 3)
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

    test('fails at once on a wrong answer, with the trace', () async {
      var runs = 0;
      await expectLater(
        run(() async {
          runs++;
          say('u1', 'One two.');
          engine
            ..start()
            ..progress(0, 3)
            ..finish();
          expect(['One'], ['One', 'two']);
        }),
        throwsA(isA<TestFailure>()),
      );
      expect(runs, 1);
      expect(resets, 0);
      expect(printed.single, startsWith('Engine trace of "a scenario":\n'));
      expect(printed.single, contains('<- range u1 0-3 "One"'));
      expect(printed.single, isNot(contains('::warning')));
    });
  });
}
