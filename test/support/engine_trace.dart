// What a real engine was told and what it reported, with the time of each,
// so a failed scenario shows the engine's side of it.
// ignore_for_file: implementation_imports
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:speak/speak.dart';
import 'package:speak/src/backend/backend.dart';
import 'package:speak/src/speak.dart' show backendFactoryOverride;

import 'test_backend.dart';

/// One scenario's record, shared by every speaker it creates.
class EngineTrace {
  final _watch = Stopwatch()..start();
  final _lines = <String>[];

  /// The texts handed to the engine, by utterance id.
  final _texts = <String, String>{};

  /// Whether the engine reported anything (an event or an interruption).
  bool get engineReported => _reported;
  bool _reported = false;

  /// Whether the engine reported an utterance started.
  bool get engineStarted => _started;
  bool _started = false;

  /// Whether anything was handed to the engine to say.
  bool get spoke => _texts.isNotEmpty;

  /// The backends not yet disposed.
  final _live = <TracingBackend>{};

  /// Stops every engine still speaking, as a scenario that failed half-way
  /// may leave one.
  Future<void> stopAll() async {
    for (final backend in _live.toList()) {
      await backend.stop();
    }
  }

  /// Starts a new record.
  void clear() {
    _lines.clear();
    _texts.clear();
    _reported = false;
    _started = false;
    _watch.reset();
  }

  void _note(String line) {
    final ms = _watch.elapsedMilliseconds.toString().padLeft(6);
    _lines.add('$ms ms  $line');
  }

  void _told(String call) => _note('-> $call');

  void _event(BackendEvent event) {
    _reported = true;
    if (event is BackendStarted) _started = true;
    final id = event.id;
    _note(
      '<- ${switch (event) {
        BackendStarted() => 'started $id',
        BackendProgress(:final start, :final end) => 'range $id $start-$end ${_word(id, start, end)}',
        BackendFinished() => 'finished $id',
        BackendCancelled() => 'cancelled $id',
        BackendFailed(:final error, :final message) => 'failed $id $error ${message ?? ''}',
      }}',
    );
  }

  String _word(String id, int start, int end) {
    final text = _texts[id];
    if (text == null || start < 0 || end > text.length || end < start) {
      return '';
    }
    return '"${text.substring(start, end)}"';
  }

  /// Every line, oldest first.
  String dump() => _lines.isEmpty ? '(nothing)' : _lines.join('\n');
}

/// Routes every [Speak] created from now on through a [TracingBackend]
/// over [testBackend], recording into [trace]; [stopTracing] undoes it.
void traceEngine(EngineTrace trace) {
  backendFactoryOverride = (android, ios) =>
      TracingBackend(testBackend(android, ios), trace);
}

/// Traces every [Speak] created from now on in this file, starting a fresh
/// record before each test; [tracedTestWidgets] prints it when one fails.
/// Called in `main` before any `setUp` that creates a speaker.
EngineTrace traceEveryTest() {
  final trace = EngineTrace();
  setUpAll(() => traceEngine(trace));
  setUp(trace.clear);
  tearDownAll(stopTracing);
  return trace;
}

/// [testWidgets], printing [trace] when [body] fails.
void tracedTestWidgets(
  String description,
  EngineTrace trace,
  WidgetTesterCallback body,
) {
  testWidgets(description, (tester) async {
    try {
      await body(tester);
    } on Object {
      debugPrint('Engine trace of "$description":\n${trace.dump()}');
      rethrow;
    }
  });
}

/// Speakers created from now on use [testBackend] untraced again.
void stopTracing() => useTestBackend();

/// The test backend, unchanged, with every call and report noted.
class TracingBackend extends DelegatingBackend {
  /// Wraps [inner].
  TracingBackend(super.inner, this._trace) {
    _trace._live.add(this);
    // Listened to before the core listens, so a report is noted first.
    _subscriptions
      ..add(inner.events.listen(_trace._event))
      ..add(
        inner.interruptions.listen((interruption) {
          _trace
            .._reported = true
            .._note('<- interruption ${interruption.name}');
        }),
      );
  }

  final EngineTrace _trace;
  final _subscriptions = <StreamSubscription<Object>>[];

  @override
  Future<AudioClaim> activateAudio(SpeakAudio audio) async {
    final claim = await inner.activateAudio(audio);
    _trace._told('activateAudio ${audio.otherAudio.name}: ${claim.name}');
    return claim;
  }

  @override
  Future<bool> isInCall() async {
    final inCall = await inner.isInCall();
    _trace._told('isInCall: $inCall');
    return inCall;
  }

  @override
  Future<void> deactivateAudio() {
    _trace._told('deactivateAudio');
    return inner.deactivateAudio();
  }

  @override
  void speak(BackendUtterance utterance) {
    final leadIn = utterance.leadIn > Duration.zero
        ? ' leadIn ${utterance.leadIn.inMilliseconds} ms'
        : '';
    // What the engine is told: volume 0 when the tests run quiet.
    final volume = inner is QuietBackend ? 0.0 : utterance.volume;
    _trace
      .._texts[utterance.id] = utterance.text
      .._told(
        'speak ${utterance.id} "${utterance.text}"$leadIn'
        '${volume == 1 ? '' : ' volume $volume'}',
      );
    inner.speak(utterance);
  }

  @override
  Future<void> stop() {
    _trace._told('stop');
    return inner.stop();
  }

  @override
  Future<void> pause() {
    _trace._told('pause');
    return inner.pause();
  }

  @override
  Future<void> resume() {
    _trace._told('resume');
    return inner.resume();
  }

  @override
  Future<void> dispose() async {
    _trace
      .._live.remove(this)
      .._told('dispose');
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    await inner.dispose();
  }
}
