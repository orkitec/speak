// The platform's backend as the real-engine tests use it: at volume 0 when
// built with --dart-define=SPEAK_TEST_QUIET=1, which the local scripts in
// tool/ pass unless given --loud (CI runs loud; nobody listens there).
// ignore_for_file: implementation_imports
import 'dart:async';

import 'package:speak/speak.dart';
import 'package:speak/src/backend/backend.dart';
import 'package:speak/src/platform/platform.dart' as platform;
import 'package:speak/src/speak.dart' show backendFactoryOverride;

/// Whether the tests speak at volume 0.
const quietTests = String.fromEnvironment('SPEAK_TEST_QUIET') == '1';

/// The platform's backend, at volume 0 when [quietTests].
SpeechBackend testBackend(AndroidSpeakOptions android, IosSpeakOptions ios) {
  final real = platform.createBackend(android, ios);
  return quietTests ? QuietBackend(real) : real;
}

/// Makes every [Speak] created from now on use [testBackend]. Each
/// integration test file calls it first.
void useTestBackend() => backendFactoryOverride = testBackend;

/// Passes everything on to [inner]; subclasses change what they need.
class DelegatingBackend implements SpeechBackend {
  /// Wraps [inner].
  DelegatingBackend(this.inner);

  /// The backend everything goes to.
  final SpeechBackend inner;

  @override
  Stream<BackendEvent> get events => inner.events;

  @override
  Stream<BackendInterruption> get interruptions => inner.interruptions;

  @override
  bool get canPause => inner.canPause;

  @override
  Future<List<Voice>> voices() => inner.voices();

  @override
  Future<VoiceAvailability?> languageAvailability(String languageTag) =>
      inner.languageAvailability(languageTag);

  @override
  Future<AudioClaim> activateAudio(SpeakAudio audio) =>
      inner.activateAudio(audio);

  @override
  Future<bool> isInCall() => inner.isInCall();

  @override
  Future<void> deactivateAudio() => inner.deactivateAudio();

  @override
  Future<bool> isBluetoothRoute(SpeakAudio audio) =>
      inner.isBluetoothRoute(audio);

  @override
  void speak(BackendUtterance utterance) => inner.speak(utterance);

  @override
  Future<void> stop() => inner.stop();

  @override
  Future<void> pause() => inner.pause();

  @override
  Future<void> resume() => inner.resume();

  @override
  Future<void> dispose() => inner.dispose();
}

/// Says everything at volume 0, otherwise unchanged: the engine still
/// synthesises and plays it, in the same time, with the same reports. The
/// lead-in is silence at any volume.
class QuietBackend extends DelegatingBackend {
  /// Wraps [inner].
  QuietBackend(super.inner);

  @override
  void speak(BackendUtterance utterance) => inner.speak(
    BackendUtterance(
      id: utterance.id,
      text: utterance.text,
      voiceId: utterance.voiceId,
      language: utterance.language,
      rate: utterance.rate,
      pitch: utterance.pitch,
      volume: 0,
      leadIn: utterance.leadIn,
    ),
  );
}
